package body Zlib.Seven_Zip_Graphs
  with SPARK_Mode => On
is
   use type Interfaces.Unsigned_64;

   function Coder_Input_Count
     (Coder : Seven_Zip_Graph_Coder) return Positive
   is
   begin
      if Coder.Method = Seven_Zip_Graph_BCJ2 then
         return 4;
      else
         return 1;
      end if;
   end Coder_Input_Count;

   function Total_Input_Streams
     (Coders : Seven_Zip_Graph_Coder_Array) return Natural
   is
      Total : Natural := 0;
   begin
      for Coder of Coders loop
         if Total > Natural'Last - Coder_Input_Count (Coder) then
            return Natural'Last;
         end if;
         Total := Total + Coder_Input_Count (Coder);
      end loop;
      return Total;
   end Total_Input_Streams;

   function Expected_Packed_Stream_Count
     (Coders     : Seven_Zip_Graph_Coder_Array;
      Bind_Pairs : Seven_Zip_Bind_Pair_Array) return Natural
   is
      Total_In : constant Natural := Total_Input_Streams (Coders);
   begin
      if Total_In >= Bind_Pairs'Length then
         return Total_In - Bind_Pairs'Length;
      else
         return 0;
      end if;
   end Expected_Packed_Stream_Count;

   function Pack_Size_Total
     (Pack_Sizes : Seven_Zip_Size_Array) return Pack_Size_Summary
   is
      Total : Interfaces.Unsigned_64 := 0;
   begin
      for Size of Pack_Sizes loop
         if Total > Interfaces.Unsigned_64'Last - Size then
            return (Total => 0, Fits => False);
         end if;
         Total := Total + Size;
      end loop;
      return (Total => Total, Fits => True);
   end Pack_Size_Total;

   function Graph_Shape_Valid
     (Coders             : Seven_Zip_Graph_Coder_Array;
      Bind_Pairs         : Seven_Zip_Bind_Pair_Array;
      Packed_Streams     : Seven_Zip_Stream_Index_Array;
      Pack_Sizes         : Seven_Zip_Size_Array;
      Unpack_Sizes       : Seven_Zip_Size_Array;
      Packed_Data_Length : Natural) return Boolean
   is
      Total_In       : constant Natural := Total_Input_Streams (Coders);
      Total_Out      : constant Natural := Coders'Length;
      Expected_Packs : constant Natural :=
        Expected_Packed_Stream_Count (Coders, Bind_Pairs);
      Packed_Total   : constant Pack_Size_Summary :=
        Pack_Size_Total (Pack_Sizes);
   begin
      if Coders'Length = 0
        or else Unpack_Sizes'Length /= Total_Out
        or else Packed_Streams'Length /= Expected_Packs
        or else Pack_Sizes'Length /= Packed_Streams'Length
        or else not Packed_Total.Fits
        or else Packed_Total.Total /= Interfaces.Unsigned_64 (Packed_Data_Length)
      then
         return False;
      end if;

      for Coder of Coders loop
         if Coder.Delta_Distance not in 1 .. 256 then
            return False;
         end if;
      end loop;

      for Pair of Bind_Pairs loop
         if Pair.In_Index >= Total_In or else Pair.Out_Index >= Total_Out then
            return False;
         end if;
      end loop;

      for Packed_Index of Packed_Streams loop
         if Packed_Index >= Total_In then
            return False;
         end if;
      end loop;

      return True;
   end Graph_Shape_Valid;

end Zlib.Seven_Zip_Graphs;
