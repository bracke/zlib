with Ada.Command_Line;
with Ada.Containers.Vectors;
with Ada.Streams; use Ada.Streams;
with Ada.Text_IO;
with Zlib;

procedure Streaming_Roundtrip_Zlib is
   use type Ada.Streams.Stream_Element_Offset;
   use type Zlib.Byte;
   use type Zlib.Status_Code;
   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Ada.Streams.Stream_Element);

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

   procedure Append_Output
     (Target : in out Byte_Vectors.Vector;
      Data   : Ada.Streams.Stream_Element_Array;
      Last   : Ada.Streams.Stream_Element_Offset)
   is
   begin
      if Last = Before_First (Data) then
         return;
      end if;

      for I in Data'First .. Last loop
         Target.Append (Data (I));
      end loop;
   end Append_Output;

   function To_Byte_Array
     (Data : Byte_Vectors.Vector)
      return Zlib.Byte_Array
   is
      Result : Zlib.Byte_Array (1 .. Natural (Data.Length));
      Pos    : Natural := Result'First;
   begin
      for B of Data loop
         Result (Pos) := Zlib.Byte (B);
         Pos := Pos + 1;
      end loop;
      return Result;
   end To_Byte_Array;

   procedure Compress_All
     (Input  : Ada.Streams.Stream_Element_Array;
      Output : in out Byte_Vectors.Vector)
   is
      Filter  : Zlib.Compression_Filter_Type;
      Buffer  : Ada.Streams.Stream_Element_Array (1 .. 2);
      In_Last : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      First   : Ada.Streams.Stream_Element_Offset := Input'First;
   begin
      Zlib.Deflate_Init (Filter, Header => Zlib.Zlib_Header, Mode => Zlib.Auto);

      while First <= Input'Last loop
         declare
            Last : constant Ada.Streams.Stream_Element_Offset :=
              Ada.Streams.Stream_Element_Offset'Min (First + 1, Input'Last);
         begin
            loop
               Zlib.Compress
                 (Filter, Input (First .. Last), In_Last, Buffer, Out_Last,
                  Zlib.No_Flush);
               Append_Output (Output, Buffer, Out_Last);
               exit when In_Last >= Last;

               if In_Last >= First then
                  First := In_Last + 1;
               elsif Out_Last = Before_First (Buffer) then
                  raise Zlib.Status_Error;
               end if;
            end loop;

            First := Last + 1;
         end;
      end loop;

      while not Zlib.Compress_Stream_End (Filter) loop
         Zlib.Compress_Flush (Filter, Buffer, Out_Last, Zlib.Finish);
         Append_Output (Output, Buffer, Out_Last);
      end loop;

      Zlib.Compress_Close (Filter);
   exception
      when others =>
         if Zlib.Is_Open (Filter) then
            Zlib.Compress_Close (Filter, Ignore_Error => True);
         end if;
         raise;
   end Compress_All;

   Plain : constant Ada.Streams.Stream_Element_Array :=
     [1 => Ada.Streams.Stream_Element (Character'Pos ('s')),
      2 => Ada.Streams.Stream_Element (Character'Pos ('t')),
      3 => Ada.Streams.Stream_Element (Character'Pos ('r')),
      4 => Ada.Streams.Stream_Element (Character'Pos ('e')),
      5 => Ada.Streams.Stream_Element (Character'Pos ('a')),
      6 => Ada.Streams.Stream_Element (Character'Pos ('m'))];
   Compressed : Byte_Vectors.Vector;
   Status     : Zlib.Status_Code;
begin
   Compress_All (Plain, Compressed);

   declare
      Decoded : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (To_Byte_Array (Compressed), Zlib.Zlib_Header, Status);
   begin
      if Status /= Zlib.Ok or else Decoded'Length /= Plain'Length then
         Ada.Text_IO.Put_Line ("roundtrip failed: " & Zlib.Status_Image (Status));
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;

      for I in Plain'Range loop
         if Decoded (Natural (I)) /= Zlib.Byte (Plain (I)) then
            Ada.Text_IO.Put_Line ("roundtrip payload mismatch");
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            return;
         end if;
      end loop;
   end;

   Ada.Text_IO.Put_Line ("streaming zlib roundtrip ok");
exception
   when Zlib.Zlib_Error =>
      Ada.Text_IO.Put_Line ("streaming zlib roundtrip zlib error");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   when Zlib.Status_Error =>
      Ada.Text_IO.Put_Line ("streaming zlib roundtrip lifecycle error");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Streaming_Roundtrip_Zlib;
