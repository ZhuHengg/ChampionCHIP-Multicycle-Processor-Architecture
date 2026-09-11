# tb/memory/ — owned by Teammate C

One testbench per module in rtl/memory/: tb_regfile.v, tb_lsu.v,
tb_address_decoder.v, tb_imem.v, tb_dmem.v.

Table 12 of the block guide gives worked DMEM load examples
(0xF1/F2/F3/F4 at 0x10010000) — use as golden vectors for tb_lsu.v.
