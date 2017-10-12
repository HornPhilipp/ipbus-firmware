-- ...
-- ...
-- Tom Williams, July 2017

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.ipbus_trans_decl.all;


entity ipbus_generic_ram_pages_if is
  generic (
  -- Number of address bits to select RX or TX buffer
  -- Number of RX and TX buffers is 2 ** INTERNALWIDTH
  BUFWIDTH: natural := 2;

  -- Number of address bits within each buffer
  -- Size of each buffer is 2**ADDRWIDTH
  ADDRWIDTH: natural := 9
  );
  port (
  	pcie_clk: in std_logic;
  	rst_pcieclk: in std_logic;
  	ipb_clk: in std_logic;
  	rst_ipb: in std_logic;

    rx_addr : in std_logic_vector(BUFWIDTH + ADDRWIDTH - 1 downto 0);
    rx_data : in std_logic_vector(31 downto 0);
    rx_we   : in std_logic;

    tx_addr : out std_logic_vector(BUFWIDTH + ADDRWIDTH downto 0);
    tx_data : out std_logic_vector(31 downto 0);
    tx_we   : out std_logic; 

    trans_out : in ipbus_trans_out;
    trans_in  : out ipbus_trans_in
  );

end ipbus_generic_ram_pages_if;



architecture rtl of ipbus_generic_ram_pages_if is

  -- meta data for publication
  SIGNAL rx_page_idx : unsigned(BUFWIDTH - 1 downto 0);
  SIGNAL tx_page_idx : unsigned(BUFWIDTH - 1 downto 0);
  SIGNAL tx_page_count : unsigned(31 downto 0);

  type header_t is array (3 downto 0) of std_logic_vector(31 downto 0);
  SIGNAL header : header_t;

  -- init
  SIGNAL init_phase : std_logic := '0';
  SIGNAL init_clk_count : unsigned(2 downto 0) := "000";

  -- rx handler
  SIGNAL rx_pkt_size : std_logic_vector(31 downto 0);
  SIGNAL rx_data_i : std_logic_vector(31 downto 0);
  SIGNAL rx_addr_i : std_logic_vector(ADDRWIDTH - 1 downto 0);
  SIGNAL rx_send_i, rx_send_i_d, rx_send_i_d2 : std_logic := '0';

  SIGNAL ram_tx_req_send : std_logic;
  SIGNAL tx_transfer_page : std_logic := '0';
  SIGNAL tx_transfer_page_d : std_logic := '0';
  SIGNAL tx_addr_local_i : std_logic_vector(ADDRWIDTH - 1 downto 0);
  SIGNAL tx_addr_global_i : std_logic_vector(BUFWIDTH + ADDRWIDTH downto 0);
  SIGNAL tx_addr_global_i_d : std_logic_vector(BUFWIDTH + ADDRWIDTH downto 0);
  SIGNAL tx_data_i : std_logic_vector(31 downto 0);
  SIGNAL tx_we_i : std_logic;
  SIGNAL tx_busy_i : std_logic;

  constant page_addr_zero : std_logic_vector(ADDRWIDTH - 1 downto 0) := (Others => '0');

  constant number_of_buffers : unsigned(31 downto 0) := to_unsigned(integer(2)**BUFWIDTH, 32);

begin

  header(0) <= std_logic_vector(to_unsigned(2**BUFWIDTH, 32));
  header(1) <= std_logic_vector(to_unsigned(2**ADDRWIDTH, 32));
  header(2) <= std_logic_vector(resize(rx_page_idx, 32));
  header(3) <= std_logic_vector(tx_page_count);

  reset_block : process (pcie_clk)
  begin
    if rising_edge(pcie_clk) then
      if rst_pcieclk = '1' then
        --rx_page_idx <= (Others => '0');
        --tx_page_idx <= (Others => '0');
        --tx_page_count <= (Others => '0');
        --rx_send_i <= '0';
        --rx_pkt_size <= (Others => '0');
        init_clk_count <= (Others => '1');
      elsif init_clk_count /= 3 then
        init_clk_count <= init_clk_count + 1;
        init_phase <= '1';
      else
        init_phase <= '0';
      end if;
    end if;
  end process reset_block;

  --process (pcie_clk)
  --begin
  --  if rising_edge(pcie_clk) then
  --    if init_clk_count /= 3 then
  --      init_clk_count <= init_clk_count + 1;
  --      init_phase <= '1';
  --    else
  --     init_phase <= '0';
  --    end if;
  --  end if;
  --end process;


  rx_addr_i <= rx_addr(ADDRWIDTH - 1 downto 0); -- converted to  - 2**BUFWIDTH;

  rx_data_i <= x"0001" & std_logic_vector((unsigned(rx_data(15 downto 0)) - 1)) when rx_addr = (std_logic_vector(rx_page_idx) & page_addr_zero) else rx_data;

  rx_pkt_size_extractor : process (pcie_clk)
  begin
    if rising_edge(pcie_clk) then
      if rst_pcieclk = '1' then
        rx_pkt_size <= (Others => '1');
      elsif rx_addr = (std_logic_vector(rx_page_idx) & page_addr_zero) then
        rx_pkt_size <= rx_data;
      else
      end if;
    end if;
  end process rx_pkt_size_extractor;

  rx_pkt_end_detector : process (pcie_clk)
  begin
    if rising_edge(pcie_clk) then
      if rst_pcieclk = '1' then
        rx_send_i <= '0';
        rx_page_idx <= (Others => '0');
      elsif rx_addr = (std_logic_vector(rx_page_idx) & std_logic_vector(resize(unsigned(rx_pkt_size),ADDRWIDTH))) then
        rx_send_i <= '1';
        rx_page_idx <= rx_page_idx + 1;
      else
        rx_send_i <= '0';
      end if;
    end if;
  end process;

  process (pcie_clk)
  begin
    if rising_edge(pcie_clk) then
      rx_send_i_d <= rx_send_i;
    end if;
  end process;

  process (pcie_clk)
  begin
    if rising_edge(pcie_clk) then
      rx_send_i_d2 <= rx_send_i_d;
    end if;
  end process;


  process (pcie_clk)
  begin
    if rising_edge(pcie_clk) then
      if tx_transfer_page = '1' then
        tx_addr <= tx_addr_global_i_d;
      else 
        tx_addr <= std_logic_vector(resize(init_clk_count, tx_addr'length));
      end if;
      tx_we <= tx_we_i or init_phase;
    end if;
  end process;
  process (pcie_clk)
  begin
    if rising_edge(pcie_clk) then
        tx_addr_global_i_d <= tx_addr_global_i;
    end if;
  end process;

  tx_addr_global_i <= std_logic_vector(4 + unsigned('0' & (std_logic_vector(tx_page_idx) & tx_addr_local_i)));
  --tx_data <= tx_data_i when tx_transfer_page = '1' else header(to_integer(init_clk_count));
  process (pcie_clk)
  begin
    if rising_edge(pcie_clk) then
      if tx_transfer_page = '1' then
        tx_data <= tx_data_i;
      elsif init_clk_count = "000" then
        tx_data <= std_logic_vector(to_unsigned(2**BUFWIDTH, 32));
      elsif init_clk_count = "001" then 
        tx_data <= std_logic_vector(to_unsigned(2**ADDRWIDTH, 32));
      elsif init_clk_count = "010" then
        tx_data <= std_logic_vector(resize(rx_page_idx, 32));
      elsif init_clk_count = "011" then
        tx_data <= std_logic_vector(tx_page_count);
      end if;
    end if;
  end process;

  process (pcie_clk)
  begin
    if rising_edge(pcie_clk) then
      tx_we_i <= (tx_transfer_page or tx_transfer_page_d);
    end if;
  end process;

  tx_pkt_rdy_detector : process (pcie_clk)
  begin
    if rising_edge(pcie_clk) then
      if rst_pcieclk = '1' then
        tx_page_idx <= (Others => '0');
        tx_page_count <= (Others => '0');
      elsif ram_tx_req_send = '1' then
        tx_transfer_page <= '1';
        tx_busy_i <= '1';
        tx_addr_local_i <= (Others => '0');
      elsif tx_addr_local_i = std_logic_vector(to_unsigned(0, ADDRWIDTH) - 1) then
        tx_transfer_page <= '0';
        tx_busy_i <= '0';
        tx_page_idx <= tx_page_idx + 1;
        tx_page_count <= tx_page_count + 1;
      else
        tx_addr_local_i <= std_logic_vector(unsigned(tx_addr_local_i) + 1);
      end if;
    end if;
  end process;

  process (pcie_clk)
  begin
    if rising_edge(pcie_clk) then
      tx_transfer_page_d <= tx_transfer_page;
    end if;
  end process;



  ipbus_ram_pkt_if : entity work.ipbus_generic_ram_if
    generic map (
      BUFWIDTH => BUFWIDTH,
      ADDRWIDTH => ADDRWIDTH
    )
    port map (
      pcie_clk => pcie_clk,
      rst_pcieclk => rst_pcieclk,
      ipb_clk => ipb_clk,
      rst_ipb => rst_ipb,

      ram_rx_addr => rx_addr_i,
      ram_rx_data => rx_data_i,
      ram_rx_reset => rst_pcieclk,
      ram_rx_payload_send => rx_send_i_d2,
      ram_rx_payload_we => rx_we,
      ram_tx_addr => tx_addr_local_i,
      ram_tx_busy => tx_busy_i,

      pkt_done => trans_out.pkt_done,
      raddr => trans_out.raddr,
      waddr => trans_out.waddr,
      wdata => trans_out.wdata,
      we => trans_out.we,

      ram_tx_data => tx_data_i,
      ram_tx_req_send => ram_tx_req_send,

      pkt_ready => trans_in.pkt_rdy,
      rdata => trans_in.rdata
    );


end rtl;