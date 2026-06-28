with Ada.Command_Line;
with Ada.Streams;
with Ada.Text_IO;
with Zlib;

procedure Streaming_Deflate_Gzip is
   use type Ada.Streams.Stream_Element_Offset;

   function Before_First
     (Data : Ada.Streams.Stream_Element_Array)
      return Ada.Streams.Stream_Element_Offset
   is
   begin
      if Data'Length = 0 or else Data'First = Ada.Streams.Stream_Element_Offset'First then
         return Data'First;
      else
         return Data'First - 1;
      end if;
   end Before_First;

   procedure Put_Output
     (Data : Ada.Streams.Stream_Element_Array;
      Last : Ada.Streams.Stream_Element_Offset)
   is
   begin
      if Last = Before_First (Data) then
         return;
      end if;

      for I in Data'First .. Last loop
         Ada.Text_IO.Put (Zlib.Byte'Image (Zlib.Byte (Data (I))));
      end loop;
   end Put_Output;

   Input : constant Ada.Streams.Stream_Element_Array :=
     [1 => Ada.Streams.Stream_Element (Character'Pos ('h')),
      2 => Ada.Streams.Stream_Element (Character'Pos ('e')),
      3 => Ada.Streams.Stream_Element (Character'Pos ('l')),
      4 => Ada.Streams.Stream_Element (Character'Pos ('l')),
      5 => Ada.Streams.Stream_Element (Character'Pos ('o'))];

   Filter : Zlib.Compression_Filter_Type;
   Output : Ada.Streams.Stream_Element_Array (1 .. 3);
   In_Last  : Ada.Streams.Stream_Element_Offset;
   Out_Last : Ada.Streams.Stream_Element_Offset;
   First    : Ada.Streams.Stream_Element_Offset := Input'First;
begin
   Zlib.Deflate_Init (Filter, Header => Zlib.GZip, Mode => Zlib.Auto);

   while First <= Input'Last loop
      declare
         Last : constant Ada.Streams.Stream_Element_Offset :=
           Ada.Streams.Stream_Element_Offset'Min (First + 1, Input'Last);
      begin
         loop
            Zlib.Compress
              (Filter, Input (First .. Last), In_Last, Output, Out_Last,
               Zlib.No_Flush);
            Put_Output (Output, Out_Last);

            exit when In_Last >= Last;

            if In_Last >= First then
               First := In_Last + 1;
            elsif Out_Last = Before_First (Output) then
               Ada.Text_IO.Put_Line ("compression made no progress");
               Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
               Zlib.Compress_Close (Filter, Ignore_Error => True);
               return;
            end if;
         end loop;

         First := Last + 1;
      end;
   end loop;

   while not Zlib.Compress_Stream_End (Filter) loop
      Zlib.Compress_Flush (Filter, Output, Out_Last, Zlib.Finish);
      Put_Output (Output, Out_Last);
   end loop;

   Ada.Text_IO.New_Line;
   Zlib.Compress_Close (Filter);
exception
   when Zlib.Zlib_Error =>
      Ada.Text_IO.Put_Line ("streaming gzip compression failed");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      if Zlib.Is_Open (Filter) then
         Zlib.Compress_Close (Filter, Ignore_Error => True);
      end if;
   when Zlib.Status_Error =>
      Ada.Text_IO.Put_Line ("streaming gzip compression lifecycle misuse");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Streaming_Deflate_Gzip;
