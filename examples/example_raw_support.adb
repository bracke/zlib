with Zlib; use Zlib;
with Ada.Containers.Vectors;
with Ada.Streams; use Ada.Streams;

package body Example_Raw_Support is
   use type Ada.Streams.Stream_Element_Offset;
   use type Zlib.Byte;

   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Ada.Streams.Stream_Element);

   function Plain return Zlib.Byte_Array is
      Text : constant String := "raw deflate example payload";
      Data : Zlib.Byte_Array (1 .. Text'Length);
   begin
      for I in Text'Range loop
         Data (I) := Zlib.Byte (Character'Pos (Text (I)));
      end loop;
      return Data;
   end Plain;

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

   function To_Stream_Array
     (Data : Zlib.Byte_Array)
      return Ada.Streams.Stream_Element_Array
   is
      Result : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Data'Length));
   begin
      for I in Data'Range loop
         Result (Ada.Streams.Stream_Element_Offset (I - Data'First + 1)) :=
           Ada.Streams.Stream_Element (Data (I));
      end loop;
      return Result;
   end To_Stream_Array;

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

   function Streaming_Compress
     (Input  : Zlib.Byte_Array;
      Header : Zlib.Header_Type;
      Mode   : Zlib.Compression_Mode)
      return Zlib.Byte_Array
   is
      Filter   : Zlib.Compression_Filter_Type;
      Source   : constant Ada.Streams.Stream_Element_Array := To_Stream_Array (Input);
      Sink     : Byte_Vectors.Vector;
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 2);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      First    : Ada.Streams.Stream_Element_Offset := Source'First;
   begin
      Zlib.Deflate_Init (Filter, Header => Header, Mode => Mode);

      while First <= Source'Last loop
         declare
            Last : constant Ada.Streams.Stream_Element_Offset :=
              Ada.Streams.Stream_Element_Offset'Min (First + 2, Source'Last);
         begin
            loop
               Zlib.Compress
                 (Filter, Source (First .. Last), In_Last, Out_Data, Out_Last,
                  Zlib.No_Flush);
               Append_Output (Sink, Out_Data, Out_Last);

               exit when In_Last >= Last;

               if In_Last >= First then
                  First := In_Last + 1;
               elsif Out_Last = Before_First (Out_Data) then
                  raise Zlib.Status_Error;
               end if;
            end loop;

            First := Last + 1;
         end;
      end loop;

      while not Zlib.Compress_Stream_End (Filter) loop
         Zlib.Compress_Flush (Filter, Out_Data, Out_Last, Zlib.Finish);
         Append_Output (Sink, Out_Data, Out_Last);
      end loop;

      Zlib.Compress_Close (Filter);
      return To_Byte_Array (Sink);
   exception
      when others =>
         if Zlib.Is_Open (Filter) then
            Zlib.Compress_Close (Filter, Ignore_Error => True);
         end if;
         raise;
   end Streaming_Compress;

   function Streaming_Inflate
     (Input  : Zlib.Byte_Array;
      Header : Zlib.Header_Type)
      return Zlib.Byte_Array
   is
      Filter   : Zlib.Filter_Type;
      Source   : constant Ada.Streams.Stream_Element_Array := To_Stream_Array (Input);
      Sink     : Byte_Vectors.Vector;
      Out_Data : Ada.Streams.Stream_Element_Array (1 .. 2);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      First    : Ada.Streams.Stream_Element_Offset := Source'First;
   begin
      Zlib.Inflate_Init (Filter, Header => Header);

      while First <= Source'Last loop
         declare
            Last : constant Ada.Streams.Stream_Element_Offset :=
              Ada.Streams.Stream_Element_Offset'Min (First + 2, Source'Last);
         begin
            loop
               Zlib.Translate
                 (Filter, Source (First .. Last), In_Last, Out_Data, Out_Last,
                  Zlib.No_Flush);
               Append_Output (Sink, Out_Data, Out_Last);

               exit when In_Last >= Last;

               if In_Last >= First then
                  First := In_Last + 1;
               elsif Out_Last = Before_First (Out_Data) then
                  raise Zlib.Status_Error;
               end if;
            end loop;

            First := Last + 1;
         end;
      end loop;

      while not Zlib.Stream_End (Filter) loop
         Zlib.Flush (Filter, Out_Data, Out_Last, Zlib.Finish);
         Append_Output (Sink, Out_Data, Out_Last);
      end loop;

      Zlib.Close (Filter);
      return To_Byte_Array (Sink);
   exception
      when others =>
         if Zlib.Is_Open (Filter) then
            Zlib.Close (Filter, Ignore_Error => True);
         end if;
         raise;
   end Streaming_Inflate;

   function Equal
     (Left  : Zlib.Byte_Array;
      Right : Zlib.Byte_Array)
      return Boolean
   is
   begin
      if Left'Length /= Right'Length then
         return False;
      end if;

      for I in Left'Range loop
         if Left (I) /= Right (Right'First + (I - Left'First)) then
            return False;
         end if;
      end loop;

      return True;
   end Equal;
end Example_Raw_Support;
