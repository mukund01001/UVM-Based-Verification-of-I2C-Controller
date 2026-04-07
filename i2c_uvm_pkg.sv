package i2c_uvm_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  typedef enum bit { I2C_WRITE = 1'b0, I2C_READ = 1'b1 } i2c_dir_e;

  class i2c_bench_cfg extends uvm_object;
    rand bit [6:0]        slave_addr;
    rand int unsigned     num_data_bytes;
    rand byte unsigned    read_payload[];

    `uvm_object_utils(i2c_bench_cfg)

    function new(string name = "i2c_bench_cfg");
      super.new(name);
      slave_addr = 7'h50;
      num_data_bytes = 2;
      read_payload = new[0];
    endfunction
  endclass

  class i2c_txn extends uvm_sequence_item;
    rand bit [6:0]        addr;
    rand i2c_dir_e        dir;
    rand byte unsigned    data[];

    `uvm_object_utils(i2c_txn)

    function new(string name = "i2c_txn");
      super.new(name);
    endfunction

    function string convert2string();
      string s;
      int i;
      s = $sformatf("addr=0x%02h dir=%s bytes=%0d",
                    addr, (dir == I2C_READ) ? "READ" : "WRITE", data.size());
      for (i = 0; i < data.size(); i++) begin
        s = {s, $sformatf(" [%0d]=0x%02h", i, data[i])};
      end
      return s;
    endfunction
  endclass

  class i2c_write_seq extends uvm_sequence #(i2c_txn);
    `uvm_object_utils(i2c_write_seq)

    function new(string name = "i2c_write_seq");
      super.new(name);
    endfunction

    task body();
      i2c_txn tr;
      tr = i2c_txn::type_id::create("tr");
      start_item(tr);
      tr.addr = 7'h50;
      tr.dir  = I2C_WRITE;
      tr.data = new[2];
      tr.data[0] = 8'hA5;
      tr.data[1] = 8'h5A;
      finish_item(tr);
    endtask
  endclass

  class i2c_read_seq extends uvm_sequence #(i2c_txn);
    `uvm_object_utils(i2c_read_seq)

    function new(string name = "i2c_read_seq");
      super.new(name);
    endfunction

    task body();
      i2c_txn tr;
      tr = i2c_txn::type_id::create("tr");
      start_item(tr);
      tr.addr = 7'h50;
      tr.dir  = I2C_READ;
      tr.data = new[2];
      tr.data[0] = 8'h11;
      tr.data[1] = 8'h22;
      finish_item(tr);
    endtask
  endclass

  class i2c_driver extends uvm_driver #(i2c_txn);
    `uvm_component_utils(i2c_driver)

    virtual i2c_if vif;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual i2c_if)::get(this, "", "vif", vif))
        `uvm_fatal("DRV", "No vif")
    endfunction

    task automatic start_cond();
      vif.master_release_all();
      vif.wait_tb_cycles(1);
      vif.master_release_scl();
      vif.master_release_sda();
      vif.wait_tb_cycles(1);
      vif.master_drive_sda_low();
      vif.wait_tb_cycles(1);
      vif.master_drive_scl_low();
      vif.wait_tb_cycles(1);
    endtask

    task automatic stop_cond();
      vif.master_drive_sda_low();
      vif.master_drive_scl_low();
      vif.wait_tb_cycles(1);
      vif.master_release_scl();
      vif.wait_tb_cycles(1);
      vif.master_release_sda();
      vif.wait_tb_cycles(1);
    endtask

    task automatic send_bit(bit b);
      if (b)
        vif.master_release_sda();
      else
        vif.master_drive_sda_low();

      vif.master_release_scl();
      vif.wait_tb_cycles(1);
      vif.master_drive_scl_low();
      vif.wait_tb_cycles(1);
    endtask

    task automatic send_byte(byte unsigned d, output bit ack_low);
      int i;
      vif.master_release_sda();
      for (i = 7; i >= 0; i--) begin
        send_bit(d[i]);
      end

      vif.master_release_sda();
      vif.master_release_scl();
      vif.wait_tb_cycles(1);
      ack_low = (vif.sample_sda() === 1'b0);
      vif.master_drive_scl_low();
      vif.wait_tb_cycles(1);
    endtask

    task automatic recv_byte(output byte unsigned d, bit master_ack_low);
      int i;
      bit b;

      d = '0;
      for (i = 7; i >= 0; i--) begin
        vif.master_release_sda();
        vif.master_release_scl();
        vif.wait_tb_cycles(1);
        b = vif.sample_sda();
        d[i] = b;
        vif.master_drive_scl_low();
        vif.wait_tb_cycles(1);
      end

      if (master_ack_low)
        vif.master_drive_sda_low();
      else
        vif.master_release_sda();

      vif.master_release_scl();
      vif.wait_tb_cycles(1);
      vif.master_drive_scl_low();
      vif.wait_tb_cycles(1);
      vif.master_release_sda();
    endtask

    task run_phase(uvm_phase phase);
      i2c_txn tr;
      bit ack_low;
      bit ack_flag;
      byte unsigned rbyte;
      int i;

      vif.master_release_all();

      forever begin
        seq_item_port.get_next_item(tr);
        `uvm_info("DRV", {"Driving ", tr.convert2string()}, UVM_LOW)

        start_cond();

        for (i = 6; i >= 0; i--) begin
          send_bit(tr.addr[i]);
        end
        send_bit(tr.dir);

        vif.master_release_sda();
        vif.master_release_scl();
        vif.wait_tb_cycles(1);
        ack_low = (vif.sample_sda() === 1'b0);
        vif.master_drive_scl_low();
        vif.wait_tb_cycles(1);

        if (tr.dir == I2C_WRITE) begin
          foreach (tr.data[idx]) begin
            send_byte(tr.data[idx], ack_low);
          end
        end
        else begin
          foreach (tr.data[idx]) begin
            ack_flag = (idx != tr.data.size()-1);
            recv_byte(rbyte, ack_flag);
          end
        end

        stop_cond();
        seq_item_port.item_done();
      end
    endtask
  endclass

  class i2c_slave_model extends uvm_component;
    `uvm_component_utils(i2c_slave_model)

    virtual i2c_if vif;
    i2c_bench_cfg cfg;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual i2c_if)::get(this, "", "vif", vif))
        `uvm_fatal("SLV", "No vif")
      if (!uvm_config_db#(i2c_bench_cfg)::get(this, "", "cfg", cfg)) begin
        cfg = i2c_bench_cfg::type_id::create("cfg");
        `uvm_warning("SLV", "No cfg found, using defaults")
      end
    endfunction

    task automatic wait_start();
      forever begin
        @(negedge vif.sda);
        if (vif.scl === 1'b1)
          return;
      end
    endtask

    task automatic wait_stop();
      forever begin
        @(posedge vif.sda);
        if (vif.scl === 1'b1)
          return;
      end
    endtask

    task automatic sample_byte(output byte unsigned b);
      int i;
      b = '0;
      for (i = 7; i >= 0; i--) begin
        @(posedge vif.scl);
        b[i] = vif.sda;
      end
    endtask

    task automatic drive_ack(bit ack_low);
      @(negedge vif.scl);
      if (ack_low)
        vif.slave_drive_sda_low();
      else
        vif.slave_release_sda();
      @(posedge vif.scl);
      @(negedge vif.scl);
      vif.slave_release_sda();
    endtask

    task automatic drive_byte(byte unsigned b);
      int i;
      for (i = 7; i >= 0; i--) begin
        @(negedge vif.scl);
        if (b[i])
          vif.slave_release_sda();
        else
          vif.slave_drive_sda_low();
        @(posedge vif.scl);
      end
      @(negedge vif.scl);
      vif.slave_release_sda();
    endtask

    task automatic sample_master_ack(output bit ack_low);
      @(posedge vif.scl);
      ack_low = (vif.sda === 1'b0);
      @(negedge vif.scl);
    endtask

    task run_phase(uvm_phase phase);
      bit [6:0] addr;
      bit dir;
      byte unsigned addr_byte;
      byte unsigned b;
      bit master_ack_low;
      int idx;
      int i;

      vif.slave_release_sda();

      forever begin
        wait_start();

        addr_byte = '0;
        for (i = 7; i >= 0; i--) begin
          @(posedge vif.scl);
          addr_byte[i] = vif.sda;
        end
        addr = addr_byte[7:1];
        dir  = addr_byte[0];

        `uvm_info("SLV",
          $sformatf("START addr=0x%02h dir=%s",
                    addr, (dir == I2C_READ) ? "READ" : "WRITE"),
          UVM_LOW)

        drive_ack(addr == cfg.slave_addr);

        if (dir == I2C_WRITE) begin
          for (idx = 0; idx < cfg.num_data_bytes; idx++) begin
            sample_byte(b);
            `uvm_info("SLV",
              $sformatf("WRITE data[%0d]=0x%02h", idx, b),
              UVM_LOW)
            drive_ack(1'b1);
          end
          wait_stop();
          `uvm_info("SLV", "STOP detected after WRITE", UVM_LOW)
        end
        else begin
          for (idx = 0; idx < cfg.num_data_bytes; idx++) begin
            if (idx < cfg.read_payload.size())
              b = cfg.read_payload[idx];
            else
              b = 8'hFF;

            `uvm_info("SLV",
              $sformatf("READ data[%0d]=0x%02h", idx, b),
              UVM_LOW)
            drive_byte(b);
            sample_master_ack(master_ack_low);
          end
          wait_stop();
          `uvm_info("SLV", "STOP detected after READ", UVM_LOW)
        end
      end
    endtask
  endclass

  class i2c_monitor extends uvm_component;
    `uvm_component_utils(i2c_monitor)

    virtual i2c_if vif;
    i2c_bench_cfg cfg;

    uvm_analysis_port #(i2c_txn) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual i2c_if)::get(this, "", "vif", vif))
        `uvm_fatal("MON", "No vif")
      if (!uvm_config_db#(i2c_bench_cfg)::get(this, "", "cfg", cfg)) begin
        cfg = i2c_bench_cfg::type_id::create("cfg");
        `uvm_warning("MON", "No cfg found, using defaults")
      end
    endfunction

    task automatic wait_start();
      forever begin
        @(negedge vif.sda);
        if (vif.scl === 1'b1)
          return;
      end
    endtask

    task automatic wait_stop();
      forever begin
        @(posedge vif.sda);
        if (vif.scl === 1'b1)
          return;
      end
    endtask

    task automatic sample_byte(output byte unsigned b);
      int i;
      b = '0;
      for (i = 7; i >= 0; i--) begin
        @(posedge vif.scl);
        b[i] = vif.sda;
      end
    endtask

    task run_phase(uvm_phase phase);
      i2c_txn tr;
      bit [6:0] addr;
      bit dir;
      byte unsigned addr_byte;
      byte unsigned b;
      bit ack_low;
      int idx;
      int i;

      forever begin
        wait_start();

        tr = i2c_txn::type_id::create("tr");
        tr.data = new[cfg.num_data_bytes];

        addr_byte = '0;
        for (i = 7; i >= 0; i--) begin
          @(posedge vif.scl);
          addr_byte[i] = vif.sda;
        end

        addr = addr_byte[7:1];
        dir  = addr_byte[0];

        tr.addr = addr;
        tr.dir  = i2c_dir_e'(dir);

        @(posedge vif.scl);
        ack_low = (vif.sda === 1'b0);

        for (idx = 0; idx < cfg.num_data_bytes; idx++) begin
          sample_byte(b);
          tr.data[idx] = b;

          @(posedge vif.scl);
          ack_low = (vif.sda === 1'b0);
        end

        wait_stop();

        `uvm_info("MON", {"Observed ", tr.convert2string()}, UVM_LOW)
        ap.write(tr);
      end
    endtask
  endclass

  class i2c_scoreboard extends uvm_component;
    `uvm_component_utils(i2c_scoreboard)

    uvm_tlm_analysis_fifo #(i2c_txn) exp_fifo;
    uvm_tlm_analysis_fifo #(i2c_txn) act_fifo;

    int unsigned pass_cnt;
    int unsigned fail_cnt;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      exp_fifo = new("exp_fifo", this);
      act_fifo = new("act_fifo", this);
      pass_cnt = 0;
      fail_cnt = 0;
    endfunction

    function bit compare_txn(i2c_txn exp, i2c_txn act);
      int i;
      if (exp.addr !== act.addr) return 0;
      if (exp.dir  !== act.dir)  return 0;
      if (exp.data.size() != act.data.size()) return 0;
      for (i = 0; i < exp.data.size(); i++) begin
        if (exp.data[i] !== act.data[i]) return 0;
      end
      return 1;
    endfunction

    task run_phase(uvm_phase phase);
      i2c_txn exp, act;
      forever begin
        exp_fifo.get(exp);
        act_fifo.get(act);

        if (compare_txn(exp, act)) begin
          pass_cnt++;
          `uvm_info("SCB", {"PASS: ", exp.convert2string()}, UVM_LOW)
        end
        else begin
          fail_cnt++;
          `uvm_error("SCB", $sformatf("MISMATCH\nEXP: %s\nACT: %s",
                                      exp.convert2string(),
                                      act.convert2string()))
        end
      end
    endtask

    function void report_phase(uvm_phase phase);
      `uvm_info("SCB",
        $sformatf("Scoreboard summary: pass=%0d fail=%0d", pass_cnt, fail_cnt),
        UVM_LOW)
    endfunction
  endclass

  class i2c_master_sequencer extends uvm_sequencer #(i2c_txn);
    `uvm_component_utils(i2c_master_sequencer)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass

  class i2c_master_agent extends uvm_component;
    `uvm_component_utils(i2c_master_agent)

    i2c_master_sequencer seqr;
    i2c_driver           drv;
    virtual i2c_if       vif;
    bit                   is_active = 1;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);

      if (!uvm_config_db#(virtual i2c_if)::get(this, "", "vif", vif))
        `uvm_fatal("AGT", "No vif")

      if (is_active) begin
        seqr = i2c_master_sequencer::type_id::create("seqr", this);
        drv  = i2c_driver::type_id::create("drv", this);
      end
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      if (is_active) begin
        drv.seq_item_port.connect(seqr.seq_item_export);
      end
    endfunction
  endclass

  class i2c_env extends uvm_env;
    `uvm_component_utils(i2c_env)

    i2c_master_agent master;
    i2c_slave_model  slave;
    i2c_monitor      mon;
    i2c_scoreboard   scb;
    i2c_bench_cfg    cfg;

    uvm_analysis_port #(i2c_txn) exp_ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      exp_ap = new("exp_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);

      if (!uvm_config_db#(i2c_bench_cfg)::get(this, "", "cfg", cfg)) begin
        cfg = i2c_bench_cfg::type_id::create("cfg");
        `uvm_warning("ENV", "No cfg found, using defaults")
      end

      uvm_config_db#(i2c_bench_cfg)::set(this, "*", "cfg", cfg);

      master = i2c_master_agent::type_id::create("master", this);
      slave  = i2c_slave_model::type_id::create("slave", this);
      mon    = i2c_monitor::type_id::create("mon", this);
      scb    = i2c_scoreboard::type_id::create("scb", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      exp_ap.connect(scb.exp_fifo.analysis_export);
      mon.ap.connect(scb.act_fifo.analysis_export);
    endfunction
  endclass

  class i2c_write_test extends uvm_test;
    `uvm_component_utils(i2c_write_test)

    i2c_env       env;
    i2c_bench_cfg cfg;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);

      cfg = i2c_bench_cfg::type_id::create("cfg");
      cfg.slave_addr = 7'h50;
      cfg.num_data_bytes = 2;
      cfg.read_payload = new[2];
      cfg.read_payload[0] = 8'h11;
      cfg.read_payload[1] = 8'h22;

      uvm_config_db#(i2c_bench_cfg)::set(this, "*", "cfg", cfg);

      env = i2c_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
      i2c_txn exp;
      i2c_write_seq seq;

      phase.raise_objection(this);

      exp = i2c_txn::type_id::create("exp");
      exp.addr = 7'h50;
      exp.dir  = I2C_WRITE;
      exp.data = new[2];
      exp.data[0] = 8'hA5;
      exp.data[1] = 8'h5A;
      env.exp_ap.write(exp);

      seq = i2c_write_seq::type_id::create("seq");
      seq.start(env.master.seqr);

      repeat (20) @(posedge env.master.vif.tb_clk);
      phase.drop_objection(this);
    endtask
  endclass

  class i2c_read_test extends uvm_test;
    `uvm_component_utils(i2c_read_test)

    i2c_env       env;
    i2c_bench_cfg cfg;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);

      cfg = i2c_bench_cfg::type_id::create("cfg");
      cfg.slave_addr = 7'h50;
      cfg.num_data_bytes = 2;
      cfg.read_payload = new[2];
      cfg.read_payload[0] = 8'h11;
      cfg.read_payload[1] = 8'h22;

      uvm_config_db#(i2c_bench_cfg)::set(this, "*", "cfg", cfg);

      env = i2c_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
      i2c_txn exp;
      i2c_read_seq seq;

      phase.raise_objection(this);

      exp = i2c_txn::type_id::create("exp");
      exp.addr = 7'h50;
      exp.dir  = I2C_READ;
      exp.data = new[2];
      exp.data[0] = 8'h11;
      exp.data[1] = 8'h22;
      env.exp_ap.write(exp);

      seq = i2c_read_seq::type_id::create("seq");
      seq.start(env.master.seqr);

      repeat (20) @(posedge env.master.vif.tb_clk);
      phase.drop_objection(this);
    endtask
  endclass

endpackage
