
toolBox.romTemplate = [[
/***************************************************************************************************
 * Module: #ROM_NAME
 *
 * Description: Sync ROM, with registered output.
 *              This is a template: macros of that kind #*** need to be replaced...
 *
 * TODO: rst is commented out for now, because not tolerated by XST...
 *
 * Created: December 13, 2009, 12:11PM
 *
 * Author: Clement Farabet
 **************************************************************************************************/
`ifndef _#ROM_NAME_ `define _#ROM_NAME_

module #ROM_NAME
  #(parameter
    CPU_ADDR_WIDTH = 32,
    ADDR_WIDTH = #ADDR_WIDTH,
    DATA_WIDTH = #DATA_WIDTH)
   (input wire clk,
    input wire rst,
    input wire [CPU_ADDR_WIDTH-1:0] address,
    output reg [DATA_WIDTH-1:0] data,
    input wire en );


    /**************************************************************************************
     * Internal address
     **************************************************************************************/
    wire [ADDR_WIDTH-1:0] addr;
    assign addr = address[ADDR_WIDTH-1:0];


    /**************************************************************************************
     * ROM Storage... a simple case statement.
     **************************************************************************************/
    always @ (posedge clk) begin : ROM_STORAGE_
        if (en) begin
            case (addr)
                #STORAGE
                default: data <= #OUTPUT_ON_RESET;
            endcase
        end
    end

endmodule

`endif //  `ifndef _#ROM_NAME_
]]
