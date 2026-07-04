// ============================================================
// branch_predictor.v  –  Branch History Table (BHT) + BTB
// ============================================================
module branch_predictor (
    input  wire        clk,
    input  wire        rst,

    // Query interface (IF stage)
    input  wire [31:0] fetch_pc,
    output wire        pred_taken,
    output wire [31:0] pred_target,

    // Update interface (ID stage when branch/jump is resolved)
    input  wire        update_en,         // 1 if instruction in ID is a branch or jump
    input  wire [31:0] update_pc,
    input  wire        update_taken,      // actual outcome
    input  wire [31:0] update_target      // actual target address
);

    // 8-entry BTB/BHT
    reg        bht [0:7];
    reg [31:0] btb_target [0:7];
    reg [26:0] btb_tag [0:7];
    reg        btb_valid [0:7];

    wire [2:0] fetch_index = fetch_pc[4:2];
    wire [26:0] fetch_tag  = fetch_pc[31:5];

    wire [2:0] update_index = update_pc[4:2];
    wire [26:0] update_tag  = update_pc[31:5];

    // Read prediction
    assign pred_taken = btb_valid[fetch_index] && 
                        (btb_tag[fetch_index] == fetch_tag) && 
                        bht[fetch_index];

    assign pred_target = pred_taken ? btb_target[fetch_index] : (fetch_pc + 32'd4);

    // Update predictor logic
    integer i;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 8; i = i + 1) begin
                bht[i]        <= 1'b0;
                btb_target[i] <= 32'b0;
                btb_tag[i]    <= 27'b0;
                btb_valid[i]  <= 1'b0;
            end
        end else if (update_en) begin
            bht[update_index] <= update_taken;
            if (update_taken) begin
                btb_target[update_index] <= update_target;
                btb_tag[update_index]    <= update_tag;
                btb_valid[update_index]  <= 1'b1;
            end else begin
                btb_valid[update_index]  <= 1'b0;
            end
        end
    end

endmodule
