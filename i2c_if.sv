interface i2c_if (input logic tb_clk);

  tri1 scl;
  tri1 sda;

  logic mst_scl_oe;
  logic mst_sda_oe;
  logic slv_sda_oe;

  assign scl = mst_scl_oe ? 1'b0 : 1'bz;
  assign sda = (mst_sda_oe || slv_sda_oe) ? 1'b0 : 1'bz;

  initial begin
    mst_scl_oe = 0;
    mst_sda_oe = 0;
    slv_sda_oe = 0;
  end

  task automatic master_release_all();
    mst_scl_oe = 0;
    mst_sda_oe = 0;
  endtask

  task automatic master_drive_scl_low();
    mst_scl_oe = 1;
  endtask

  task automatic master_release_scl();
    mst_scl_oe = 0;
  endtask

  task automatic master_drive_sda_low();
    mst_sda_oe = 1;
  endtask

  task automatic master_release_sda();
    mst_sda_oe = 0;
  endtask

  task automatic slave_drive_sda_low();
    slv_sda_oe = 1;
  endtask

  task automatic slave_release_sda();
    slv_sda_oe = 0;
  endtask

  task automatic wait_tb_cycles(int unsigned n);
    repeat (n) @(posedge tb_clk);
  endtask

  function automatic bit sample_scl();
    return scl;
  endfunction

  function automatic bit sample_sda();
    return sda;
  endfunction

endinterface
