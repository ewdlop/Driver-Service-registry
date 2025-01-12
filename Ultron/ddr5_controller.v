// DDR5 DRAM Controller for FPGA
// Supports basic DDR5 operations with timing parameters

module ddr5_controller #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 64,  // DDR5 typically uses 64-bit data width
    parameter BURST_LENGTH = 16 // DDR5 burst length
) (
    input wire clk_sys,              // System clock
    input wire clk_mem,              // Memory clock (typically higher frequency)
    input wire rst_n,                // Active low reset
    
    // Host interface
    input  wire [ADDR_WIDTH-1:0] addr_in,
    input  wire [DATA_WIDTH-1:0] data_in,
    output wire [DATA_WIDTH-1:0] data_out,
    input  wire                  cmd_valid,
    input  wire                  cmd_read,
    output wire                  cmd_ready,
    
    // DDR5 interface
    output wire [17:0] ddr_addr,     // Address bus
    inout  wire [63:0] ddr_data,     // Data bus
    output wire [1:0]  ddr_bank,     // Bank address
    output wire [1:0]  ddr_bank_group,
    output wire        ddr_cs_n,     // Chip select
    output wire        ddr_ras_n,    // Row address strobe
    output wire        ddr_cas_n,    // Column address strobe
    output wire        ddr_we_n,     // Write enable
    output wire        ddr_reset_n,  // Reset signal
    output wire        ddr_ck_p,     // Differential clock
    output wire        ddr_ck_n,
    output wire        ddr_cke,      // Clock enable
    output wire        ddr_odt       // On-die termination
);

    // DDR5 Timing Parameters (in memory clock cycles)
    localparam tCK = 1;      // Clock cycle time
    localparam tRCD = 14;    // RAS to CAS delay
    localparam tRP = 14;     // Row precharge time
    localparam tRAS = 32;    // Row active time
    localparam tRC = 46;     // Row cycle time
    localparam tWR = 16;     // Write recovery time
    localparam tRTP = 8;     // Read to precharge time
    
    // State machine definition
    typedef enum logic [3:0] {
        IDLE,
        ACTIVATE,
        READ,
        WRITE,
        PRECHARGE,
        REFRESH,
        POWER_DOWN,
        SELF_REFRESH
    } state_t;
    
    state_t current_state, next_state;
    
    // Internal registers
    reg [17:0] row_addr;
    reg [9:0]  col_addr;
    reg [1:0]  bank_addr;
    reg [1:0]  bank_group;
    reg [DATA_WIDTH-1:0] write_data;
    reg [DATA_WIDTH-1:0] read_data;
    reg [7:0]  timer;
    reg        data_valid;
    
    // Command encoding
    localparam CMD_MRS    = 4'b0000;
    localparam CMD_REF    = 4'b0001;
    localparam CMD_PRE    = 4'b0010;
    localparam CMD_ACT    = 4'b0011;
    localparam CMD_WR     = 4'b0100;
    localparam CMD_RD     = 4'b0101;
    localparam CMD_NOP    = 4'b0111;
    
    // Address decoding
    always @(posedge clk_mem) begin
        if (!rst_n) begin
            row_addr <= 18'h0;
            col_addr <= 10'h0;
            bank_addr <= 2'h0;
            bank_group <= 2'h0;
        end else if (cmd_valid) begin
            row_addr <= addr_in[27:10];
            col_addr <= addr_in[9:0];
            bank_addr <= addr_in[29:28];
            bank_group <= addr_in[31:30];
        end
    end
    
    // State machine
    always @(posedge clk_mem or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            timer <= 8'h0;
        end else begin
            current_state <= next_state;
            
            case (current_state)
                ACTIVATE: begin
                    if (timer != 0)
                        timer <= timer - 1;
                end
                
                READ, WRITE: begin
                    if (timer != 0)
                        timer <= timer - 1;
                end
                
                PRECHARGE: begin
                    if (timer != 0)
                        timer <= timer - 1;
                end
                
                default: timer <= 8'h0;
            endcase
        end
    end
    
    // Next state logic
    always @(*) begin
        case (current_state)
            IDLE: begin
                if (cmd_valid)
                    next_state = ACTIVATE;
                else
                    next_state = IDLE;
            end
            
            ACTIVATE: begin
                if (timer == 0) begin
                    if (cmd_read)
                        next_state = READ;
                    else
                        next_state = WRITE;
                end else
                    next_state = ACTIVATE;
            end
            
            READ: begin
                if (timer == 0)
                    next_state = PRECHARGE;
                else
                    next_state = READ;
            end
            
            WRITE: begin
                if (timer == 0)
                    next_state = PRECHARGE;
                else
                    next_state = WRITE;
            end
            
            PRECHARGE: begin
                if (timer == 0)
                    next_state = IDLE;
                else
                    next_state = PRECHARGE;
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // Command output logic
    always @(posedge clk_mem) begin
        case (current_state)
            IDLE: begin
                ddr_cs_n <= 1'b1;
                ddr_ras_n <= 1'b1;
                ddr_cas_n <= 1'b1;
                ddr_we_n <= 1'b1;
            end
            
            ACTIVATE: begin
                ddr_cs_n <= 1'b0;
                ddr_ras_n <= 1'b0;
                ddr_cas_n <= 1'b1;
                ddr_we_n <= 1'b1;
                ddr_addr <= row_addr;
                ddr_bank <= bank_addr;
                ddr_bank_group <= bank_group;
            end
            
            READ: begin
                ddr_cs_n <= 1'b0;
                ddr_ras_n <= 1'b1;
                ddr_cas_n <= 1'b0;
                ddr_we_n <= 1'b1;
                ddr_addr <= {8'h0, col_addr};
            end
            
            WRITE: begin
                ddr_cs_n <= 1'b0;
                ddr_ras_n <= 1'b1;
                ddr_cas_n <= 1'b0;
                ddr_we_n <= 1'b0;
                ddr_addr <= {8'h0, col_addr};
                write_data <= data_in;
            end
            
            PRECHARGE: begin
                ddr_cs_n <= 1'b0;
                ddr_ras_n <= 1'b0;
                ddr_cas_n <= 1'b1;
                ddr_we_n <= 1'b0;
                ddr_addr <= 18'h400; // Precharge all banks
            end
        endcase
    end
    
    // Data path
    assign ddr_data = (current_state == WRITE) ? write_data : {DATA_WIDTH{1'bz}};
    assign data_out = read_data;
    
    // Read data capture
    always @(posedge clk_mem) begin
        if (current_state == READ && !ddr_cas_n)
            read_data <= ddr_data;
    end
    
    // Clock output
    assign ddr_ck_p = clk_mem;
    assign ddr_ck_n = ~clk_mem;
    
    // Additional control signals
    assign ddr_cke = 1'b1;      // Clock always enabled
    assign ddr_reset_n = rst_n;  // Reset signal
    assign ddr_odt = 1'b1;      // On-die termination enabled
    
    // Command ready signal
    assign cmd_ready = (current_state == IDLE);

endmodule

// Testbench
module ddr5_controller_tb;
    reg clk_sys;
    reg clk_mem;
    reg rst_n;
    reg [31:0] addr_in;
    reg [63:0] data_in;
    wire [63:0] data_out;
    reg cmd_valid;
    reg cmd_read;
    wire cmd_ready;
    
    // Instantiate DDR5 controller
    ddr5_controller ddr5_inst (
        .clk_sys(clk_sys),
        .clk_mem(clk_mem),
        .rst_n(rst_n),
        .addr_in(addr_in),
        .data_in(data_in),
        .data_out(data_out),
        .cmd_valid(cmd_valid),
        .cmd_read(cmd_read),
        .cmd_ready(cmd_ready)
    );
    
    // Clock generation
    initial begin
        clk_sys = 0;
        clk_mem = 0;
        forever begin
            #5 clk_sys = ~clk_sys;
            #2.5 clk_mem = ~clk_mem;  // Memory clock runs at 2x frequency
        end
    end
    
    // Test sequence
    initial begin
        // Initialize
        rst_n = 0;
        cmd_valid = 0;
        cmd_read = 0;
        addr_in = 0;
        data_in = 0;
        
        // Reset release
        #100 rst_n = 1;
        
        // Write test
        #100;
        addr_in = 32'h0000_0000;
        data_in = 64'hDEAD_BEEF_1234_5678;
        cmd_valid = 1;
        cmd_read = 0;
        
        // Wait for command ready
        @(posedge cmd_ready);
        cmd_valid = 0;
        
        // Read test
        #100;
        addr_in = 32'h0000_0000;
        cmd_valid = 1;
        cmd_read = 1;
        
        // Wait for command ready
        @(posedge cmd_ready);
        cmd_valid = 0;
        
        // End simulation
        #1000 $finish;
    end
    
    // Monitor
    initial begin
        $monitor("Time=%0t cmd_ready=%b data_out=%h",
                 $time, cmd_ready, data_out);
    end
endmodule
