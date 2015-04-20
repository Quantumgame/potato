-- The Potato Processor - A simple processor for FPGAs
-- (c) Kristian Klomsten Skordal 2014 - 2015 <kristian.skordal@wafflemail.net>
-- Report bugs and issues on <https://github.com/skordal/potato/issues>

library ieee;
use ieee.std_logic_1164.all;

use work.pp_types.all;
use work.pp_constants.all;
use work.pp_csr.all;

--! @brief Unit decoding instructions and setting control signals apropriately.
entity pp_control_unit is
	port(
		-- Inputs, indices correspond to instruction word indices:
		opcode  : in std_logic_vector( 4 downto 0);
		funct3  : in std_logic_vector( 2 downto 0);
		funct7  : in std_logic_vector( 6 downto 0);
		funct12 : in std_logic_vectoR(11 downto 0);

		-- Control signals:
		rd_write            : out std_logic;
		branch              : out branch_type;

		-- Exception signals:
		decode_exception       : out std_logic;
		decode_exception_cause : out std_logic_vector(4 downto 0);

		-- Control register signals:
		csr_write : out csr_write_mode;
		csr_imm   : out std_logic; --! Indicating an immediate variant of the csrr* instructions.

		-- Sources of operands to the ALU:
		alu_x_src, alu_y_src : out alu_operand_source;

		-- ALU operation:
		alu_op : out alu_operation;

		-- Memory transaction parameters:
		mem_op   : out memory_operation_type;
		mem_size : out memory_operation_size
	);
end entity pp_control_unit;

architecture behaviour of pp_control_unit is
begin

	csr_imm <= funct3(2);

	alu_control: entity work.pp_alu_control_unit
		port map(
			opcode => opcode,
			funct3 => funct3,
			funct7 => funct7,
			alu_x_src => alu_x_src,
			alu_y_src => alu_y_src,
			alu_op => alu_op
		);

	decode_ctrl: process(opcode, funct3, funct12)
	begin
		case opcode is
			when b"01101" => -- Load upper immediate
				rd_write <= '1';
				decode_exception <= '0';
				decode_exception_cause <= CSR_CAUSE_NONE;
				branch <= BRANCH_NONE;
			when b"00101" => -- Add upper immediate to PC
				rd_write <= '1';
				decode_exception <= '0';
				decode_exception_cause <= CSR_CAUSE_NONE;
				branch <= BRANCH_NONE;
			when b"11011" => -- Jump and link
				rd_write <= '1';
				decode_exception <= '0';
				decode_exception_cause <= CSR_CAUSE_NONE;
				branch <= BRANCH_JUMP;
			when b"11001" => -- Jump and link register
				rd_write <= '1';
				decode_exception <= '0';
				decode_exception_cause <= CSR_CAUSE_NONE;
				branch <= BRANCH_JUMP_INDIRECT;
			when b"11000" => -- Branch operations
				rd_write <= '0';
				decode_exception <= '0';
				decode_exception_cause <= CSR_CAUSE_NONE;
				branch <= BRANCH_CONDITIONAL;
			when b"00000" => -- Load instructions
				rd_write <= '1';
				decode_exception <= '0';
				decode_exception_cause <= CSR_CAUSE_NONE;
				branch <= BRANCH_NONE;
			when b"01000" => -- Store instructions
				rd_write <= '0';
				decode_exception <= '0';
				decode_exception_cause <= CSR_CAUSE_NONE;
				branch <= BRANCH_NONE;
			when b"00100" => -- Register-immediate operations
				rd_write <= '1';
				decode_exception <= '0';
				decode_exception_cause <= CSR_CAUSE_NONE;
				branch <= BRANCH_NONE;
			when b"01100" => -- Register-register operations
				rd_write <= '1';
				decode_exception <= '0';
				decode_exception_cause <= CSR_CAUSE_NONE;
				branch <= BRANCH_NONE;
			when b"00011" => -- Fence instructions, ignored
				rd_write <= '0';
				decode_exception <= '0';
				decode_exception_cause <= CSR_CAUSE_NONE;
				branch <= BRANCH_NONE;
			when b"11100" => -- System instructions
				if funct3 = b"000" then
					rd_write <= '0';

					if funct12 = x"000" then
						decode_exception <= '1';
						decode_exception_cause <= CSR_CAUSE_SYSCALL;
						branch <= BRANCH_NONE;
					elsif funct12 = x"001" then
						decode_exception <= '1';
						decode_exception_cause <= CSR_CAUSE_BREAKPOINT;
						branch <= BRANCH_NONE;
					elsif funct12 = x"800" then
						decode_exception <= '0';
						decode_exception_cause <= CSR_CAUSE_NONE;
						branch <= BRANCH_SRET;
					else
						decode_exception <= '1';
						decode_exception_cause <= CSR_CAUSE_INVALID_INSTR;
						branch <= BRANCH_NONE;
					end if;
				else
					rd_write <= '1';
					decode_exception <= '0';
					decode_exception_cause <= CSR_CAUSE_NONE;
					branch <= BRANCH_NONE;
				end if;
			when others =>
				rd_write <= '0';
				decode_exception <= '1';
				decode_exception_cause <= CSR_CAUSE_INVALID_INSTR;
				branch <= BRANCH_NONE;
		end case;
	end process decode_ctrl;

	decode_csr: process(opcode, funct3)
	begin
		if opcode = b"11100" then
			case funct3 is
				when b"001" | b"101" => -- csrrw/i
					csr_write <= CSR_WRITE_REPLACE;
				when b"010" | b"110" => -- csrrs/i
					csr_write <= CSR_WRITE_SET;
				when b"011" | b"111" => -- csrrc/i
					csr_write <= CSR_WRITE_CLEAR;
				when others =>
					csr_write <= CSR_WRITE_NONE;
			end case;
		else
			csr_write <= CSR_WRITE_NONE;
		end if;
	end process decode_csr;

	decode_mem: process(opcode, funct3)
	begin
		case opcode is
			when b"00000" => -- Load instructions
				case funct3 is
					when b"000" => -- lw
						mem_size <= MEMOP_SIZE_BYTE;
						mem_op <= MEMOP_TYPE_LOAD;
					when b"001" => -- lh
						mem_size <= MEMOP_SIZE_HALFWORD;
						mem_op <= MEMOP_TYPE_LOAD;
					when b"010" | b"110" => -- lw
						mem_size <= MEMOP_SIZE_WORD;
						mem_op <= MEMOP_TYPE_LOAD;
					when b"100" => -- lbu
						mem_size <= MEMOP_SIZE_BYTE;
						mem_op <= MEMOP_TYPE_LOAD_UNSIGNED;
					when b"101" => -- lhu
						mem_size <= MEMOP_SIZE_HALFWORD;
						mem_op <= MEMOP_TYPE_LOAD_UNSIGNED;
					when others => -- FIXME: Treat others as lw.
						mem_size <= MEMOP_SIZE_WORD;
						mem_op <= MEMOP_TYPE_INVALID;
				end case;
			when b"01000" => -- Store instructions
				case funct3 is
					when b"000" =>
						mem_op <= MEMOP_TYPE_STORE;
						mem_size <= MEMOP_SIZE_BYTE;
					when b"001" =>
						mem_op <= MEMOP_TYPE_STORE;
						mem_size <= MEMOP_SIZE_HALFWORD;
					when b"010" =>
						mem_op <= MEMOP_TYPE_STORE;
						mem_size <= MEMOP_SIZE_WORD;
					when others =>
						mem_op <= MEMOP_TYPE_INVALID;
						mem_size <= MEMOP_SIZE_WORD;
				end case;
			when others =>
				mem_op <= MEMOP_TYPE_NONE;
				mem_size <= MEMOP_SIZE_WORD;
		end case;
	end process decode_mem;

end architecture behaviour;
