with Ada.Command_Line;
with Ada.Streams;
with Ada.Text_IO;
with Zlib;

procedure Streaming_Inflate_Gzip is
   use type Ada.Streams.Stream_Element_Offset;

   GZip_Hello : constant Zlib.Byte_Array :=
     [1 => 16#1F#, 2 => 16#8B#, 3 => 16#08#, 4 => 16#00#,
      5 => 16#00#, 6 => 16#00#, 7 => 16#00#, 8 => 16#00#,
      9 => 16#00#, 10 => 16#FF#, 11 => 16#CB#, 12 => 16#48#,
      13 => 16#CD#, 14 => 16#C9#, 15 => 16#C9#, 16 => 16#07#,
      17 => 16#00#, 18 => 16#86#, 19 => 16#A6#, 20 => 16#10#,
      21 => 16#36#, 22 => 16#05#, 23 => 16#00#, 24 => 16#00#,
      25 => 16#00#];

   Filter : Zlib.Filter_Type;

   function Before_First
     (Data : Ada.Streams.Stream_Element_Array)
      return Ada.Streams.Stream_Element_Offset
   is
   begin
      if Data'Length = 0 then
         return Data'First;
      elsif Data'First = Ada.Streams.Stream_Element_Offset'First then
         return Data'First;
      else
         return Data'First - 1;
      end if;
   end Before_First;

   procedure Print_Output
     (Data : Ada.Streams.Stream_Element_Array;
      Last : Ada.Streams.Stream_Element_Offset)
   is
   begin
      if Last = Before_First (Data) then
         return;
      end if;

      for I in Data'First .. Last loop
         Ada.Text_IO.Put (Character'Val (Integer (Data (I))));
      end loop;
   end Print_Output;

   function Output_Is_Hello
     (Data : Ada.Streams.Stream_Element_Array;
      Last : Ada.Streams.Stream_Element_Offset)
      return Boolean
   is
      Expected : constant String := "hello";
   begin
      if Last = Before_First (Data) then
         return False;
      end if;

      if Natural (Last - Data'First + 1) /= Expected'Length then
         return False;
      end if;

      for I in Expected'Range loop
         if Character'Val
              (Integer (Data (Data'First + Ada.Streams.Stream_Element_Offset (I - 1))))
            /= Expected (I)
         then
            return False;
         end if;
      end loop;

      return True;
   end Output_Is_Hello;

begin
   Zlib.Inflate_Init (Filter, Header => Zlib.GZip);

   declare
      In_Data  : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (GZip_Hello'Length));
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 64);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
   begin
      for I in GZip_Hello'Range loop
         In_Data (Ada.Streams.Stream_Element_Offset (I)) :=
           Ada.Streams.Stream_Element (GZip_Hello (I));
      end loop;

      Zlib.Translate (Filter, In_Data, In_Last, Out_Data, Out_Last, Zlib.Finish);

      if In_Last /= In_Data'Last then
         Ada.Text_IO.Put_Line ("streaming gzip did not consume the full input");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         Zlib.Close (Filter, Ignore_Error => True);
         return;
      end if;

      if not Zlib.Stream_End (Filter) then
         Ada.Text_IO.Put_Line ("streaming gzip did not reach stream end");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         Zlib.Close (Filter, Ignore_Error => True);
         return;
      end if;

      if not Output_Is_Hello (Out_Data, Out_Last) then
         Ada.Text_IO.Put_Line ("streaming gzip decoded unexpected payload");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         Zlib.Close (Filter, Ignore_Error => True);
         return;
      end if;

      Print_Output (Out_Data, Out_Last);
      Ada.Text_IO.New_Line;
      Zlib.Close (Filter);
   end;
exception
   when Zlib.Zlib_Error =>
      Ada.Text_IO.Put_Line ("streaming gzip inflate failed");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      if Zlib.Is_Open (Filter) then
         Zlib.Close (Filter, Ignore_Error => True);
      end if;
   when Zlib.Status_Error =>
      Ada.Text_IO.Put_Line ("streaming gzip lifecycle misuse");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Streaming_Inflate_Gzip;
