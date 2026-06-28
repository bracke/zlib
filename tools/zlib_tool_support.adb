with Zlib;
with Ada.Directories;
with Ada.Streams; use Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Containers.Vectors;

package body Zlib_Tool_Support is
   package SIO renames Ada.Streams.Stream_IO;
   use type Ada.Streams.Stream_Element_Offset;

   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Ada.Streams.Stream_Element);

   function Empty return Zlib.Byte_Array is
      Result : constant Zlib.Byte_Array (1 .. 0) := [others => 0];
   begin
      return Result;
   end Empty;

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
     (Input : Zlib.Byte_Array)
      return Ada.Streams.Stream_Element_Array
   is
      Result : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Input'Length));
      Pos    : Ada.Streams.Stream_Element_Offset := Result'First;
   begin
      for I in Input'Range loop
         Result (Pos) := Ada.Streams.Stream_Element (Input (I));
         Pos := Pos + 1;
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

   function Read_File
     (Path   : String;
      Status : out Zlib.Status_Code)
      return Zlib.Byte_Array
   is
      File : SIO.File_Type;
   begin
      if not Ada.Directories.Exists (Path) then
         Status := Zlib.Input_File_Error;
         return Empty;
      end if;

      SIO.Open (File, SIO.In_File, Path);

      declare
         Size : constant Natural := Natural (SIO.Size (File));
      begin
         if Size = 0 then
            SIO.Close (File);
            Status := Zlib.Ok;
            return Empty;
         end if;

         declare
            Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Size));
            Last   : Ada.Streams.Stream_Element_Offset;
            Result : Zlib.Byte_Array (1 .. Size);
         begin
            SIO.Read (File, Buffer, Last);
            SIO.Close (File);

            for I in Result'Range loop
               Result (I) := Zlib.Byte (Buffer (Ada.Streams.Stream_Element_Offset (I)));
            end loop;

            Status := Zlib.Ok;
            return Result;
         end;
      end;
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         Status := Zlib.Input_File_Error;
         return Empty;
   end Read_File;

   procedure Write_File
     (Path   : String;
      Data   : Zlib.Byte_Array;
      Status : out Zlib.Status_Code)
   is
      File : SIO.File_Type;
   begin
      SIO.Create (File, SIO.Out_File, Path);

      if Data'Length > 0 then
         declare
            Buffer : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Data'Length));
         begin
            for I in Data'Range loop
               Buffer (Ada.Streams.Stream_Element_Offset (I - Data'First + 1)) :=
                 Ada.Streams.Stream_Element (Data (I));
            end loop;
            SIO.Write (File, Buffer);
         end;
      end if;

      SIO.Close (File);
      Status := Zlib.Ok;
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         Status := Zlib.Output_File_Error;
   end Write_File;

   function Mode_From_Option
     (Option : String;
      Status : out Zlib.Status_Code)
      return Zlib.Compression_Mode
   is
   begin
      Status := Zlib.Ok;
      if Option = "--mode=stored" then
         return Zlib.Stored;
      elsif Option = "--mode=fixed" then
         return Zlib.Fixed;
      elsif Option = "--mode=dynamic" then
         return Zlib.Dynamic;
      elsif Option = "--mode=auto" then
         return Zlib.Auto;
      else
         Status := Zlib.Invalid_Header;
         return Zlib.Auto;
      end if;
   end Mode_From_Option;


   function Level_From_Option
     (Option : String;
      Status : out Zlib.Status_Code)
      return Zlib.Compression_Level
   is
      Prefix : constant String := "--level=";
   begin
      Status := Zlib.Ok;
      if Option'Length = Prefix'Length + 1
        and then Option (Option'First .. Option'First + Prefix'Length - 1) = Prefix
        and then Option (Option'Last) in '0' .. '9'
      then
         return Zlib.Compression_Level
           (Character'Pos (Option (Option'Last)) - Character'Pos ('0'));
      else
         Status := Zlib.Invalid_Header;
         return Zlib.Default_Level;
      end if;
   end Level_From_Option;

   function Streaming_Compress
     (Input  : Zlib.Byte_Array;
      Header : Zlib.Header_Type;
      Mode   : Zlib.Compression_Mode)
      return Zlib.Byte_Array
   is
      Filter     : Zlib.Compression_Filter_Type;
      Source     : constant Ada.Streams.Stream_Element_Array := To_Stream_Array (Input);
      Sink       : Byte_Vectors.Vector;
      Out_Data   : Ada.Streams.Stream_Element_Array (1 .. 3);
      In_Last    : Ada.Streams.Stream_Element_Offset;
      Out_Last   : Ada.Streams.Stream_Element_Offset;
      First      : Ada.Streams.Stream_Element_Offset := Source'First;
   begin
      Zlib.Deflate_Init (Filter, Header => Header, Mode => Mode);

      while First <= Source'Last loop
         declare
            Last : constant Ada.Streams.Stream_Element_Offset :=
              Ada.Streams.Stream_Element_Offset'Min (First + 4, Source'Last);
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

   function Streaming_Compress
     (Input  : Zlib.Byte_Array;
      Header : Zlib.Header_Type;
      Level  : Zlib.Compression_Level)
      return Zlib.Byte_Array
   is
      Filter     : Zlib.Compression_Filter_Type;
      Source     : constant Ada.Streams.Stream_Element_Array := To_Stream_Array (Input);
      Sink       : Byte_Vectors.Vector;
      Out_Data   : Ada.Streams.Stream_Element_Array (1 .. 3);
      In_Last    : Ada.Streams.Stream_Element_Offset;
      Out_Last   : Ada.Streams.Stream_Element_Offset;
      First      : Ada.Streams.Stream_Element_Offset := Source'First;
   begin
      Zlib.Deflate_Init (Filter, Header => Header, Level => Level);

      while First <= Source'Last loop
         declare
            Last : constant Ada.Streams.Stream_Element_Offset :=
              Ada.Streams.Stream_Element_Offset'Min (First + 4, Source'Last);
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

end Zlib_Tool_Support;
