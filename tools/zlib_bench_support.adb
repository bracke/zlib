with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Zlib; use Zlib;

package body Zlib_Bench_Support is
   package SIO renames Ada.Streams.Stream_IO;
   use type Ada.Streams.Stream_Element_Offset;

   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Zlib.Byte);

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

   function Produced
     (Data : Ada.Streams.Stream_Element_Array;
      Last : Ada.Streams.Stream_Element_Offset)
      return Natural
   is
   begin
      if Data'Length = 0 or else Last = Before_First (Data) then
         return 0;
      end if;

      return Natural (Last - Data'First + 1);
   end Produced;

   function Consumed
     (Data : Ada.Streams.Stream_Element_Array;
      Last : Ada.Streams.Stream_Element_Offset)
      return Natural
   is
   begin
      if Data'Length = 0 or else Last = Before_First (Data) then
         return 0;
      end if;

      return Natural (Last - Data'First + 1);
   end Consumed;

   procedure Append_Output
     (Target : in out Byte_Vectors.Vector;
      Data   : Ada.Streams.Stream_Element_Array;
      Last   : Ada.Streams.Stream_Element_Offset)
   is
   begin
      if Data'Length = 0 or else Last = Before_First (Data) then
         return;
      end if;

      for I in Data'First .. Last loop
         Target.Append (Zlib.Byte (Data (I)));
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
         Result (Pos) := B;
         Pos := Pos + 1;
      end loop;

      return Result;
   end To_Byte_Array;

   function Header_For (Wrapper : Wrapper_Kind) return Zlib.Header_Type is
   begin
      case Wrapper is
         when Wrapper_Zlib =>
            return Zlib.Zlib_Header;
         when Wrapper_Gzip =>
            return Zlib.GZip;
         when Wrapper_Raw =>
            return Zlib.Raw_Deflate;
      end case;
   end Header_For;

   function Wrapper_Image (Wrapper : Wrapper_Kind) return String is
   begin
      case Wrapper is
         when Wrapper_Zlib => return "zlib";
         when Wrapper_Gzip => return "gzip";
         when Wrapper_Raw  => return "raw";
      end case;
   end Wrapper_Image;

   function Mode_Image (Mode : Zlib.Compression_Mode) return String is
   begin
      case Mode is
         when Zlib.Stored  => return "stored";
         when Zlib.Fixed   => return "fixed";
         when Zlib.Dynamic => return "dynamic";
         when Zlib.Auto    => return "auto";
      end case;
   end Mode_Image;

   function Ratio (Compressed_Bytes, Input_Bytes : Natural) return Long_Float is
   begin
      if Input_Bytes = 0 then
         return 0.0;
      end if;
      return Long_Float (Compressed_Bytes) * 100.0 / Long_Float (Input_Bytes);
   end Ratio;

   function Throughput_MiB_S (Bytes : Natural; Seconds : Duration) return Long_Float is
   begin
      if Seconds <= 0.0 then
         return 0.0;
      end if;
      return Long_Float (Bytes) / 1_048_576.0 / Long_Float (Seconds);
   end Throughput_MiB_S;

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

            if Last /= Buffer'Last then
               Status := Zlib.Input_File_Error;
               return Empty;
            end if;

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

   function Synthetic_Data (Pattern : Pattern_Kind; Size : Natural) return Zlib.Byte_Array is
      Result : Zlib.Byte_Array (1 .. Size);
      Text   : constant String :=
        "The quick brown fox jumps over the lazy dog. Ada zlib benchmark text. ";
   begin
      for I in Result'Range loop
         case Pattern is
            when Pattern_Randomish =>
               Result (I) := Zlib.Byte ((I * 73 + 19) mod 256);
            when Pattern_Repeated =>
               Result (I) := Zlib.Byte (Character'Pos ('A') + (I mod 4));
            when Pattern_Text_Like =>
               Result (I) := Zlib.Byte
                 (Character'Pos (Text (((I - 1) mod Text'Length) + Text'First)));
         end case;
      end loop;

      return Result;
   end Synthetic_Data;

   function Starts_With (Text, Prefix : String) return Boolean is
   begin
      return Text'Length >= Prefix'Length
        and then Text (Text'First .. Text'First + Prefix'Length - 1) = Prefix;
   end Starts_With;

   function Option_Value (Text, Prefix : String) return String is
   begin
      return Text (Text'First + Prefix'Length .. Text'Last);
   end Option_Value;

   function Parse_Wrapper (Value : String; Ok : out Boolean) return Wrapper_Kind is
   begin
      Ok := True;
      if Value = "zlib" then
         return Wrapper_Zlib;
      elsif Value = "gzip" then
         return Wrapper_Gzip;
      elsif Value = "raw" then
         return Wrapper_Raw;
      else
         Ok := False;
         return Wrapper_Zlib;
      end if;
   end Parse_Wrapper;

   function Parse_Mode (Value : String; Ok : out Boolean) return Zlib.Compression_Mode is
   begin
      Ok := True;
      if Value = "stored" then
         return Zlib.Stored;
      elsif Value = "fixed" then
         return Zlib.Fixed;
      elsif Value = "dynamic" then
         return Zlib.Dynamic;
      elsif Value = "auto" then
         return Zlib.Auto;
      else
         Ok := False;
         return Zlib.Auto;
      end if;
   end Parse_Mode;

   function Parse_Level (Value : String; Ok : out Boolean) return Zlib.Compression_Level is
      N : Natural;
   begin
      Ok := Value'Length = 1 and then Value (Value'First) in '0' .. '9';
      if not Ok then
         return Zlib.Default_Level;
      end if;

      N := Character'Pos (Value (Value'First)) - Character'Pos ('0');
      return Zlib.Compression_Level (N);
   end Parse_Level;

   function Parse_Natural (Value : String; Ok : out Boolean) return Natural is
      Result : Natural := 0;
   begin
      Ok := Value'Length > 0;
      for C of Value loop
         if C not in '0' .. '9' then
            Ok := False;
            return 0;
         end if;
         Result := Result * 10 + Character'Pos (C) - Character'Pos ('0');
      end loop;
      return Result;
   exception
      when Constraint_Error =>
         Ok := False;
         return 0;
   end Parse_Natural;

   function Parse_Positive (Value : String; Ok : out Boolean) return Positive is
      N : constant Natural := Parse_Natural (Value, Ok);
   begin
      if Ok and then N > 0 then
         return Positive (N);
      else
         Ok := False;
         return 1;
      end if;
   end Parse_Positive;

   function Parse_Pattern (Value : String; Ok : out Boolean) return Pattern_Kind is
   begin
      Ok := True;
      if Value = "random-ish" then
         return Pattern_Randomish;
      elsif Value = "repeated" then
         return Pattern_Repeated;
      elsif Value = "text-like" then
         return Pattern_Text_Like;
      else
         Ok := False;
         return Pattern_Randomish;
      end if;
   end Parse_Pattern;

   function Streaming_Compress
     (Input        : Zlib.Byte_Array;
      Config       : Compression_Config;
      Status       : out Zlib.Status_Code)
      return Zlib.Byte_Array
   is
      Filter   : Zlib.Compression_Filter_Type;
      Sink     : Byte_Vectors.Vector;
      Position : Natural := Input'First;
   begin
      if Config.Use_Level then
         Zlib.Deflate_Init
           (Filter, Header => Header_For (Config.Wrapper), Level => Config.Level);
      else
         Zlib.Deflate_Init
           (Filter, Header => Header_For (Config.Wrapper), Mode => Config.Mode);
      end if;

      while Position <= Input'Last loop
         declare
            Count : constant Natural := Natural'Min
              (Config.Input_Chunk, Input'Last - Position + 1);
            In_Data : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Count));
            Out_Data : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Config.Output_Chunk));
            In_Last  : Ada.Streams.Stream_Element_Offset;
            Out_Last : Ada.Streams.Stream_Element_Offset;
         begin
            for I in 0 .. Count - 1 loop
               In_Data (Ada.Streams.Stream_Element_Offset (I + 1)) :=
                 Ada.Streams.Stream_Element (Input (Position + I));
            end loop;

            Zlib.Compress
              (Filter, In_Data, In_Last, Out_Data, Out_Last, Zlib.No_Flush);
            Append_Output (Sink, Out_Data, Out_Last);

            declare
               Used : constant Natural := Consumed (In_Data, In_Last);
               Made : constant Natural := Produced (Out_Data, Out_Last);
            begin
               if Used > 0 then
                  Position := Position + Used;
               elsif Made = 0 then
                  Status := Zlib.Output_File_Error;
                  Zlib.Compress_Close (Filter, Ignore_Error => True);
                  return Empty;
               end if;
            end;
         end;
      end loop;

      while not Zlib.Compress_Stream_End (Filter) loop
         declare
            Out_Data : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Config.Output_Chunk));
            Out_Last : Ada.Streams.Stream_Element_Offset;
         begin
            Zlib.Compress_Flush (Filter, Out_Data, Out_Last, Zlib.Finish);
            Append_Output (Sink, Out_Data, Out_Last);
         end;
      end loop;

      Zlib.Compress_Close (Filter);
      Status := Zlib.Ok;
      return To_Byte_Array (Sink);
   exception
      when others =>
         if Zlib.Is_Open (Filter) then
            Zlib.Compress_Close (Filter, Ignore_Error => True);
         end if;
         Status := Zlib.Output_File_Error;
         return Empty;
   end Streaming_Compress;

   function Streaming_Inflate
     (Input        : Zlib.Byte_Array;
      Config       : Inflate_Config;
      Status       : out Zlib.Status_Code)
      return Zlib.Byte_Array
   is
      Filter   : Zlib.Filter_Type;
      Sink     : Byte_Vectors.Vector;
      Position : Natural := Input'First;
   begin
      Zlib.Inflate_Init (Filter, Header => Header_For (Config.Wrapper));

      while Position <= Input'Last loop
         declare
            Count : constant Natural := Natural'Min
              (Config.Input_Chunk, Input'Last - Position + 1);
            In_Data : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Count));
            Out_Data : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Config.Output_Chunk));
            In_Last  : Ada.Streams.Stream_Element_Offset;
            Out_Last : Ada.Streams.Stream_Element_Offset;
         begin
            for I in 0 .. Count - 1 loop
               In_Data (Ada.Streams.Stream_Element_Offset (I + 1)) :=
                 Ada.Streams.Stream_Element (Input (Position + I));
            end loop;

            Zlib.Translate
              (Filter, In_Data, In_Last, Out_Data, Out_Last, Zlib.No_Flush);
            Append_Output (Sink, Out_Data, Out_Last);

            declare
               Used : constant Natural := Consumed (In_Data, In_Last);
               Made : constant Natural := Produced (Out_Data, Out_Last);
            begin
               if Used > 0 then
                  Position := Position + Used;
               elsif Made = 0 then
                  Status := Zlib.Unexpected_End_Of_Input;
                  Zlib.Close (Filter, Ignore_Error => True);
                  return Empty;
               end if;
            end;
         end;
      end loop;

      while not Zlib.Stream_End (Filter) loop
         declare
            Empty_In : constant Ada.Streams.Stream_Element_Array (1 .. 0) := [];
            Out_Data : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Config.Output_Chunk));
            In_Last  : Ada.Streams.Stream_Element_Offset;
            Out_Last : Ada.Streams.Stream_Element_Offset;
         begin
            Zlib.Translate
              (Filter, Empty_In, In_Last, Out_Data, Out_Last, Zlib.Finish);
            Append_Output (Sink, Out_Data, Out_Last);

            if Produced (Out_Data, Out_Last) = 0 and then not Zlib.Stream_End (Filter) then
               Status := Zlib.Unexpected_End_Of_Input;
               Zlib.Close (Filter, Ignore_Error => True);
               return Empty;
            end if;
         end;
      end loop;

      Zlib.Close (Filter);
      Status := Zlib.Ok;
      return To_Byte_Array (Sink);
   exception
      when others =>
         if Zlib.Is_Open (Filter) then
            Zlib.Close (Filter, Ignore_Error => True);
         end if;
         Status := Zlib.Unexpected_End_Of_Input;
         return Empty;
   end Streaming_Inflate;
end Zlib_Bench_Support;
