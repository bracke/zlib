--  Support level: private internal implementation.
--
--  Validation helpers for caller-supplied 7z folder graphs. This package keeps
--  low-level graph arithmetic out of the container writer.

with Interfaces;

package Zlib.Seven_Zip_Graphs
  with SPARK_Mode => On
is

   function Coder_Input_Count
     (Coder : Seven_Zip_Graph_Coder) return Positive;
   --  Return the number of input streams consumed by Coder.

   function Total_Input_Streams
     (Coders : Seven_Zip_Graph_Coder_Array) return Natural;
   --  Return the total input-stream count for the coder list.

   function Expected_Packed_Stream_Count
     (Coders     : Seven_Zip_Graph_Coder_Array;
      Bind_Pairs : Seven_Zip_Bind_Pair_Array) return Natural;
   --  Return the number of packed streams implied by the coder input streams
   --  and bind pairs. Malformed over-bound graphs return zero.

   type Pack_Size_Summary is record
      Total : Interfaces.Unsigned_64 := 0;
      Fits  : Boolean := True;
   end record;
   --  Packed-size sum plus overflow status.

   function Pack_Size_Total
     (Pack_Sizes : Seven_Zip_Size_Array) return Pack_Size_Summary;
   --  Sum Pack_Sizes. Fits is False when the sum would overflow UInt64.

   function Graph_Shape_Valid
     (Coders             : Seven_Zip_Graph_Coder_Array;
      Bind_Pairs         : Seven_Zip_Bind_Pair_Array;
      Packed_Streams     : Seven_Zip_Stream_Index_Array;
      Pack_Sizes         : Seven_Zip_Size_Array;
      Unpack_Sizes       : Seven_Zip_Size_Array;
      Packed_Data_Length : Natural) return Boolean;
   --  Return True when the folder graph metadata is internally consistent.

end Zlib.Seven_Zip_Graphs;
