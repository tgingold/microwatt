library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;

entity register_file is
    generic (
        SIM : boolean := false
        );
    port(
        clk           : in std_logic;

        d_in          : in Decode2ToRegisterFileType;
        d_out         : out RegisterFileToDecode2Type;

        w_in          : in WritebackToRegisterFileType;

        -- debug
        sim_dump      : in std_ulogic
        );
end entity register_file;

architecture behaviour of register_file is
    type regfile is array(0 to 32) of std_ulogic_vector(63 downto 0);
    signal registers : regfile := (others => (others => '0'));
begin
    -- synchronous writes
    register_write_0: process(clk)
    begin
        if rising_edge(clk) then
            if w_in.write_enable = '1' then
                assert not(is_x(w_in.write_data)) and not(is_x(w_in.write_reg)) severity failure;
                report "Writing GPR " & to_hstring(w_in.write_reg) & " " & to_hstring(w_in.write_data);
                registers(to_integer(unsigned(w_in.write_reg))) <= w_in.write_data;
            end if;
        end if;
    end process register_write_0;

    -- asynchronous reads
    register_read_0: process(all)
    begin
        if d_in.read1_enable = '1' then
            report "Reading GPR " & to_hstring(d_in.read1_reg) & " " & to_hstring(registers(to_integer(unsigned(d_in.read1_reg))));
        end if;
        if d_in.read2_enable = '1' then
            report "Reading GPR " & to_hstring(d_in.read2_reg) & " " & to_hstring(registers(to_integer(unsigned(d_in.read2_reg))));
        end if;
        if d_in.read3_enable = '1' then
            report "Reading GPR " & to_hstring(d_in.read3_reg) & " " & to_hstring(registers(to_integer(unsigned(d_in.read3_reg))));
        end if;
        d_out.read1_data <= registers(to_integer(unsigned(d_in.read1_reg)));
        d_out.read2_data <= registers(to_integer(unsigned(d_in.read2_reg)));
        d_out.read3_data <= registers(to_integer(unsigned(d_in.read3_reg)));

        -- Forward any written data
        if w_in.write_enable = '1' then
            if d_in.read1_reg = w_in.write_reg then
                d_out.read1_data <= w_in.write_data;
            end if;
            if d_in.read2_reg = w_in.write_reg then
                d_out.read2_data <= w_in.write_data;
            end if;
            if d_in.read3_reg = w_in.write_reg then
                d_out.read3_data <= w_in.write_data;
            end if;
        end if;
    end process register_read_0;

    -- Dump registers if core terminates
    sim_dump_test: if SIM generate
	dump_registers: process(all)
	begin
	    if sim_dump = '1' then
		loop_0: for i in 0 to 31 loop
		    report "REG " & to_hstring(registers(i));
		end loop loop_0;
		assert false report "end of test" severity failure;
	    end if;
	end process;
    end generate;

end architecture behaviour;
