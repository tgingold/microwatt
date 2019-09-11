library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.all;

use std.textio.all;

library work;
use work.common.all;
use work.wishbone_types.all;


-- 0x00000000: Main memory (1 MB)
-- 0xc0002000: UART0 (for host communication)
entity soc is
    generic (
	MEMORY_SIZE   : positive;
	RAM_INIT_FILE : string;
	RESET_LOW     : boolean;
	SIM           : boolean
	);
    port(
	rst          : in  std_ulogic;
	system_clk   : in  std_ulogic;

	-- UART0 signals:
	uart0_txd    : out std_ulogic;
	uart0_rxd    : in  std_ulogic
	);
end entity soc;

architecture behaviour of soc is

    -- Wishbone master signals:
    signal wishbone_dcore_in : wishbone_slave_out;
    signal wishbone_dcore_out : wishbone_master_out;
    signal wishbone_icore_in : wishbone_slave_out;
    signal wishbone_icore_out : wishbone_master_out;

    -- Wishbone master (output of arbiter):
    signal wb_master_in : wishbone_slave_out;
    signal wb_master_out : wishbone_master_out;

    -- UART0 signals:
    signal wb_uart0_in   : wishbone_master_out;
    signal wb_uart0_out  : wishbone_slave_out;
    signal uart_dat8     : std_ulogic_vector(7 downto 0);

    -- Main memory signals:
    signal wb_bram_in     : wishbone_master_out;
    signal wb_bram_out    : wishbone_slave_out;
    constant mem_adr_bits : positive := positive(ceil(log2(real(MEMORY_SIZE))));

    -- Debug signals (used in SIM only)
    signal registers     : regfile;
    signal terminate     : std_ulogic;

begin

    -- Processor core
    processor: entity work.core
	generic map(
	    SIM => SIM
	    )
	port map(
	    clk => system_clk,
	    rst => rst,
	    wishbone_insn_in => wishbone_icore_in,
	    wishbone_insn_out => wishbone_icore_out,
	    wishbone_data_in => wishbone_dcore_in,
	    wishbone_data_out => wishbone_dcore_out,
	    registers => registers,
	    terminate_out => terminate
	    );

    -- Wishbone bus master arbiter & mux
    wishbone_arbiter_0: entity work.wishbone_arbiter
	port map(
	    clk => system_clk,
	    rst => rst,
	    wb1_in => wishbone_dcore_out,
	    wb1_out => wishbone_dcore_in,
	    wb2_in => wishbone_icore_out,
	    wb2_out => wishbone_icore_in,
	    wb_out => wb_master_out,
	    wb_in => wb_master_in
	    );

    -- Wishbone slaves address decoder & mux
    slave_intercon: process(wb_master_out, wb_bram_out, wb_uart0_out)
	-- Selected slave
	type slave_type is (SLAVE_UART,
			    SLAVE_MEMORY,
			    SLAVE_NONE);
	variable slave : slave_type;
    begin
	-- Simple address decoder
	slave := SLAVE_NONE;
	if wb_master_out.adr(63 downto 24) = x"0000000000" then
	    slave := SLAVE_MEMORY;
	elsif wb_master_out.adr(63 downto 24) = x"00000000c0" then
	    if wb_master_out.adr(15 downto 12) = x"2" then
		slave := SLAVE_UART;
	    end if;
	end if;

	-- Wishbone muxing. Defaults:
	wb_bram_in <= wb_master_out;
	wb_bram_in.cyc  <= '0';
	wb_uart0_in <= wb_master_out;
	wb_uart0_in.cyc <= '0';
	case slave is
	when SLAVE_MEMORY =>
	    wb_bram_in.cyc <= wb_master_out.cyc;
	    wb_master_in <= wb_bram_out;
	when SLAVE_UART =>
	    wb_uart0_in.cyc <= wb_master_out.cyc;
	    wb_master_in <= wb_uart0_out;
	when others =>
	    wb_master_in.dat <= (others => '1');
	    wb_master_in.ack <= wb_master_out.stb and wb_master_out.cyc;
	end case;
    end process slave_intercon;

    -- Simulated memory and UART
    sim_terminate_test: if SIM generate

	-- Dump registers if core terminates
	dump_registers: process(all)
	begin
	    if terminate = '1' then
		loop_0: for i in 0 to 31 loop
		    report "REG " & to_hstring(registers(i));
		end loop loop_0;
		assert false report "end of test" severity failure;
	    end if;
	end process;

    end generate;

    -- UART0 wishbone slave
    -- XXX FIXME: Need a proper wb64->wb8 adapter that
    --            converts SELs into low address bits and muxes
    --            data accordingly (either that or rejects large
    --            cycles).
    uart0: entity work.pp_soc_uart
	generic map(
	    FIFO_DEPTH => 32
	    )
	port map(
	    clk => system_clk,
	    reset => rst,
	    txd => uart0_txd,
	    rxd => uart0_rxd,
	    wb_adr_in => wb_uart0_in.adr(11 downto 0),
	    wb_dat_in => wb_uart0_in.dat(7 downto 0),
	    wb_dat_out => uart_dat8,
	    wb_cyc_in => wb_uart0_in.cyc,
	    wb_stb_in => wb_uart0_in.stb,
	    wb_we_in => wb_uart0_in.we,
	    wb_ack_out => wb_uart0_out.ack
	    );
    wb_uart0_out.dat <= x"00000000000000" & uart_dat8;

    -- BRAM Memory slave
    bram0: entity work.mw_soc_memory
	generic map(
	    MEMORY_SIZE   => MEMORY_SIZE,
	    RAM_INIT_FILE => RAM_INIT_FILE
	    )
	port map(
	    clk => system_clk,
	    rst => rst,
	    wishbone_in => wb_bram_in,
	    wishbone_out => wb_bram_out
	    );

end architecture behaviour;