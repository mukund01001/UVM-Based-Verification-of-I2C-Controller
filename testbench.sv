`include "i2c_if.sv"
`include "i2c_uvm_pkg.sv"

`include "uvm_macros.svh"
import uvm_pkg::*;
import i2c_uvm_pkg::*;

module tb_top;

  bit clk = 0;
  always #5 clk = ~clk;

  i2c_if vif(clk);
string testname;
initial begin
  testname = "i2c_write_test";
    void'($value$plusargs("TESTNAME=%s", testname));
    uvm_config_db#(virtual i2c_if)::set(null, "*", "vif", vif);
    run_test(testname);
  end

endmodule
