with Ada.Containers.Vectors;
with Ada.Streams;
with Ada.Strings.Unbounded;
with CryptoLib.Checksums;
with Zlib.Seven_Zip_Coders;
with Zlib.Seven_Zip_Graphs;
with Zlib.Seven_Zip_Numbers;
with Zlib.Seven_Zip_Paths;

package body Zlib.Seven_Zip_Container is
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;

   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Byte);
   package US renames Ada.Strings.Unbounded;

   function To_Byte_Array (Data : Byte_Vectors.Vector) return Byte_Array
   is
      Output : Byte_Array (1 .. Natural (Data.Length));
      Pos    : Natural := Output'First;
   begin
      for B of Data loop
         Output (Pos) := B;
         Pos := Pos + 1;
      end loop;

      return Output;
   end To_Byte_Array;

   procedure Append_Bytes
     (Output : in out Byte_Vectors.Vector;
      Data   : Byte_Array) is
   begin
      for B of Data loop
         Output.Append (B);
      end loop;
   end Append_Bytes;

   function Compute_CRC32 (Data : Byte_Array) return Interfaces.Unsigned_32 is
      State : CryptoLib.Checksums.CRC32_State;
   begin
      CryptoLib.Checksums.CRC32_Reset (State);
      for B of Data loop
         CryptoLib.Checksums.CRC32_Update (State, Ada.Streams.Stream_Element (B));
      end loop;
      return CryptoLib.Checksums.CRC32_Value (State);
   end Compute_CRC32;

   procedure Append_Number
     (Output : in out Byte_Vectors.Vector;
      Value  : Interfaces.Unsigned_64) is
   begin
      Append_Bytes (Output, Zlib.Seven_Zip_Numbers.Encode_Number (Value));
   end Append_Number;

   procedure Append_U32_LE
     (Output : in out Byte_Vectors.Vector;
      Value  : Interfaces.Unsigned_32)
   is
      V : Interfaces.Unsigned_32 := Value;
   begin
      for I in 1 .. 4 loop
         pragma Unreferenced (I);
         Output.Append (Byte (V mod 256));
         V := V / 256;
      end loop;
   end Append_U32_LE;

   procedure Put_U32_LE
     (Output : in out Byte_Array;
      Pos    : in out Natural;
      Value  : Interfaces.Unsigned_32)
     with
       SPARK_Mode => On,
       Pre        => Pos in Output'Range
         and then Pos <= Natural'Last - 4
         and then Output'Last - Pos >= 3,
       Post       => Pos = Pos'Old + 4
   is
      V : Interfaces.Unsigned_32 := Value;
   begin
      for I in 1 .. 4 loop
         pragma Unreferenced (I);
         Output (Pos) := Byte (V mod 256);
         V := V / 256;
         Pos := Pos + 1;
      end loop;
   end Put_U32_LE;

   procedure Put_U64_LE
     (Output : in out Byte_Array;
      Pos    : in out Natural;
      Value  : Interfaces.Unsigned_64)
     with
       SPARK_Mode => On,
       Pre        => Pos in Output'Range
         and then Pos <= Natural'Last - 8
         and then Output'Last - Pos >= 7,
       Post       => Pos = Pos'Old + 8
   is
      V : Interfaces.Unsigned_64 := Value;
   begin
      for I in 1 .. 8 loop
         pragma Unreferenced (I);
         Output (Pos) := Byte (V mod 256);
         V := V / 256;
         Pos := Pos + 1;
      end loop;
   end Put_U64_LE;

   function UTF16LE_NT (Text : String) return Byte_Array
   is
      Output : Byte_Array (1 .. Text'Length * 2 + 2);
      Pos    : Natural := Output'First;
   begin
      for Ch of Text loop
         Output (Pos) := Byte (Character'Pos (Ch) mod 256);
         Output (Pos + 1) := Byte (Character'Pos (Ch) / 256);
         Pos := Pos + 2;
      end loop;

      Output (Pos) := 0;
      Output (Pos + 1) := 0;
      return Output;
   end UTF16LE_NT;

   function Packed_Bits
     (Bits  : Boolean_Array;
      Count : Natural) return Byte_Array
   is
      Output     : Byte_Array (1 .. (Count + 7) / 8);
      Byte_Value : Natural := 0;
      Pos        : Natural := Output'First;
   begin
      if Count = 0 then
         return [1 .. 0 => 0];
      end if;

      for I in 1 .. Count loop
         if Bits (Bits'First + I - 1) then
            Byte_Value := Byte_Value + 2 ** (7 - ((I - 1) mod 8));
         end if;

         if I mod 8 = 0 then
            Output (Pos) := Byte (Byte_Value);
            Pos := Pos + 1;
            Byte_Value := 0;
         end if;
      end loop;

      if Count mod 8 /= 0 then
         Output (Pos) := Byte (Byte_Value);
      end if;

      return Output;
   end Packed_Bits;

   function Read_Byte
     (Data : Byte_Array;
      Pos  : in out Natural;
      Last : Natural;
      B    : out Byte) return Boolean
   is
   begin
      if Pos > Last then
         B := 0;
         return False;
      end if;

      B := Data (Pos);
      Pos := Pos + 1;
      return True;
   end Read_Byte;

   function Expect_Byte
     (Data     : Byte_Array;
      Pos      : in out Natural;
      Last     : Natural;
      Expected : Byte) return Boolean
   is
      Actual : Byte := 0;
   begin
      return Read_Byte (Data, Pos, Last, Actual)
        and then Actual = Expected;
   end Expect_Byte;

   function Has_Bytes
     (Pos   : Natural;
      Last  : Natural;
      Count : Natural) return Boolean
     with SPARK_Mode => On
   is
   begin
      return Count = 0
        or else (Pos <= Last and then Count - 1 <= Last - Pos);
   end Has_Bytes;

   function Find_Signature
     (Data : Byte_Array;
      Pos  : out Natural) return Boolean
   is
   begin
      Pos := 0;

      if Data'Length < 33 then
         return False;
      end if;

      for I in Data'First .. Data'Last - 31 loop
         if Data (I) = 16#37#
           and then Data (I + 1) = 16#7A#
           and then Data (I + 2) = 16#BC#
           and then Data (I + 3) = 16#AF#
           and then Data (I + 4) = 16#27#
           and then Data (I + 5) = 16#1C#
           and then Data (I + 6) = 0
           and then Data (I + 7) = 4
           and then (I = Data'First
                     or else Zlib.Seven_Zip_Numbers.U32_At (Data, I + 8) =
                       Compute_CRC32 (Data (I + 12 .. I + 31)))
         then
            Pos := I;
            return True;
         end if;
      end loop;

      return False;
   end Find_Signature;

   function Has_Archive_Signature (Data : Byte_Array) return Boolean
     with SPARK_Mode => On
   is
   begin
      return
        Data'Length >= 6
        and then Data (Data'First) = 16#37#
        and then Data (Data'First + 1) = 16#7A#
        and then Data (Data'First + 2) = 16#BC#
        and then Data (Data'First + 3) = 16#AF#;
   end Has_Archive_Signature;

   function Skip_Properties
     (Data : Byte_Array;
      Pos  : in out Natural;
      Last : Natural) return Boolean
   is
      Property : Byte := 0;
      Size     : Interfaces.Unsigned_64 := 0;
   begin
      loop
         if not Read_Byte (Data, Pos, Last, Property) then
            return False;
         end if;

         exit when Property = 0;

         if not Zlib.Seven_Zip_Numbers.Read_Number (Data, Pos, Last, Size)
           or else Size > Interfaces.Unsigned_64 (Natural'Last)
           or else Size > Interfaces.Unsigned_64 (Last - Pos + 1)
         then
            return False;
         end if;

         Pos := Pos + Natural (Size);
      end loop;

      return True;
   end Skip_Properties;

   function Read_Start_Header
     (Archive       : Byte_Array;
      Signature_Pos : Natural;
      Info          : out Start_Header_Info;
      Status        : in out Status_Code) return Boolean
   is
      Start_First : constant Natural := Signature_Pos + 12;
      Start_Last  : constant Natural := Signature_Pos + 31;
      Payload_First : constant Natural := Signature_Pos + 32;
   begin
      Info := (others => <>);

      if Signature_Pos > Archive'Last
        or else Archive'Last - Signature_Pos + 1 < 33
      then
         Status := Unexpected_End_Of_Input;
         return False;
      end if;

      declare
         Start       : constant Byte_Array := Archive (Start_First .. Start_Last);
         Start_CRC   : constant Interfaces.Unsigned_32 :=
           Zlib.Seven_Zip_Numbers.U32_At (Archive, Signature_Pos + 8);
         Offset      : constant Interfaces.Unsigned_64 :=
           Zlib.Seven_Zip_Numbers.U64_At (Archive, Signature_Pos + 12);
         Header_Size : constant Interfaces.Unsigned_64 :=
           Zlib.Seven_Zip_Numbers.U64_At (Archive, Signature_Pos + 20);
         Header_CRC  : constant Interfaces.Unsigned_32 :=
           Zlib.Seven_Zip_Numbers.U32_At (Archive, Signature_Pos + 28);
      begin
         if Start_CRC /= Compute_CRC32 (Start) then
            Status := Invalid_Checksum;
            return False;
         end if;

         if Offset > Interfaces.Unsigned_64 (Natural'Last)
           or else Header_Size > Interfaces.Unsigned_64 (Natural'Last)
           or else Offset > Interfaces.Unsigned_64 (Natural'Last - Payload_First)
         then
            Status := Unsupported_Method;
            return False;
         end if;

         declare
            Payload_Count : constant Natural := Natural (Offset);
            Header_Count  : constant Natural := Natural (Header_Size);
            Header_First  : constant Natural := Payload_First + Payload_Count;
         begin
            if Header_Count = 0
              or else Header_First > Archive'Last
              or else Header_Count > Natural'Last - Header_First + 1
            then
               Status := Unexpected_End_Of_Input;
               return False;
            end if;

            declare
               Header_Last : constant Natural := Header_First + Header_Count - 1;
            begin
               if Header_Last > Archive'Last then
                  Status := Unexpected_End_Of_Input;
                  return False;
               end if;

               if Header_Last /= Archive'Last then
                  Status := Unsupported_Method;
                  return False;
               end if;

               if Header_CRC /= Compute_CRC32 (Archive (Header_First .. Header_Last)) then
                  Status := Invalid_Checksum;
                  return False;
               end if;

               Info :=
                 (Payload_First => Payload_First,
                  Header_First  => Header_First,
                  Header_Last   => Header_Last,
                  Payload_Count => Payload_Count,
                  Header_Count  => Header_Count,
                  Header_CRC    => Header_CRC);
               return True;
            end;
         end;
      end;
   end Read_Start_Header;

   function Build_Archive
     (Header  : Byte_Array;
      Payload : Byte_Array) return Byte_Array
   is
      Header_CRC   : constant Interfaces.Unsigned_32 := Compute_CRC32 (Header);
      Start_Header : Byte_Array (1 .. 20);
      Start_Pos    : Natural := Start_Header'First;
   begin
      Put_U64_LE (Start_Header, Start_Pos, Interfaces.Unsigned_64 (Payload'Length));
      Put_U64_LE (Start_Header, Start_Pos, Interfaces.Unsigned_64 (Header'Length));
      Put_U32_LE (Start_Header, Start_Pos, Header_CRC);

      declare
         Start_CRC : constant Interfaces.Unsigned_32 := Compute_CRC32 (Start_Header);
         Archive   : Byte_Array (1 .. 32 + Payload'Length + Header'Length);
         Pos       : Natural := Archive'First;
      begin
         Archive (Pos .. Pos + 5) := [16#37#, 16#7A#, 16#BC#, 16#AF#, 16#27#, 16#1C#];
         Pos := Pos + 6;
         Archive (Pos) := 0;
         Pos := Pos + 1;
         Archive (Pos) := 4;
         Pos := Pos + 1;
         Put_U32_LE (Archive, Pos, Start_CRC);
         Archive (Pos .. Pos + Start_Header'Length - 1) := Start_Header;
         Pos := Pos + Start_Header'Length;

         if Payload'Length > 0 then
            Archive (Pos .. Pos + Payload'Length - 1) := Payload;
            Pos := Pos + Payload'Length;
         end if;

         if Header'Length > 0 then
            Archive (Pos .. Pos + Header'Length - 1) := Header;
         end if;

         return Archive;
      end;
   end Build_Archive;

   function Header_Only_Entry
     (Entry_Name : String;
      Metadata   : Seven_Zip_Entry_Metadata;
      Status     : out Status_Code) return Byte_Array
   is
      Empty      : constant Byte_Array (1 .. 0) := [others => 0];
      Header     : Byte_Vectors.Vector;
      Name_Field : Byte_Vectors.Vector;
   begin
      Status := Unsupported_Method;

      if not Zlib.Seven_Zip_Paths.Entry_Name_Valid (Entry_Name)
        or else not Metadata.Is_Directory
      then
         return Empty;
      end if;

      Header.Append (16#01#); --  Header
      Header.Append (16#05#); --  FilesInfo
      Append_Number (Header, 1);
      Header.Append (16#11#); --  Name
      Name_Field.Append (0);
      Append_Bytes (Name_Field, UTF16LE_NT (Entry_Name));
      Append_Number (Header, Interfaces.Unsigned_64 (Name_Field.Length));
      Header.Append_Vector (Name_Field);
      Header.Append (16#0E#); --  EmptyStream
      Append_Number (Header, 1);
      Header.Append (16#80#);
      Header.Append (16#0F#); --  EmptyFile
      Append_Number (Header, 1);
      Header.Append (0);
      Append_Bytes (Header, Zlib.Seven_Zip_Properties.Metadata_Image (Metadata));
      Header.Append (0);
      Header.Append (0);

      declare
         Header_Image : constant Byte_Array := To_Byte_Array (Header);
      begin
         Status := Ok;
         return Build_Archive (Header_Image, Empty);
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Header_Only_Entry;

   function Single_File_Archive
     (Packed_Data   : Byte_Array;
      Unpacked_Data : Byte_Array;
      Entry_Name    : String;
      Method        : Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;
      Metadata      : Seven_Zip_Entry_Metadata;
      Status        : out Status_Code;
      LZMA_Props    : Byte) return Byte_Array
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];
   begin
      Status := Unsupported_Method;

      if not Zlib.Seven_Zip_Paths.Entry_Name_Valid (Entry_Name) then
         return Empty;
      end if;

      if Metadata.Is_Directory then
         return Header_Only_Entry (Entry_Name, Metadata, Status);
      end if;

      declare
         Packed_CRC   : constant Interfaces.Unsigned_32 := Compute_CRC32 (Packed_Data);
         Unpacked_CRC : constant Interfaces.Unsigned_32 := Compute_CRC32 (Unpacked_Data);
         Header       : Byte_Vectors.Vector;
         Name_Field   : Byte_Vectors.Vector;
      begin
         Header.Append (16#01#); --  Header

         Header.Append (16#04#); --  MainStreamsInfo
         Header.Append (16#06#); --  PackInfo
         Append_Number (Header, 0);
         Append_Number (Header, 1);
         Header.Append (16#09#); --  Size
         Append_Number (Header, Interfaces.Unsigned_64 (Packed_Data'Length));
         Header.Append (16#0A#); --  CRC
         Header.Append (1);
         Append_U32_LE (Header, Packed_CRC);
         Header.Append (0);

         Header.Append (16#07#); --  UnPackInfo
         Header.Append (16#0B#); --  Folder
         Append_Number (Header, 1);
         Header.Append (0);
         Append_Number (Header, 1);
         Append_Bytes
           (Header, Zlib.Seven_Zip_Coders.Descriptor_Bytes (Method, LZMA_Props));
         Header.Append (16#0C#); --  CodersUnPackSize
         Append_Number (Header, Interfaces.Unsigned_64 (Unpacked_Data'Length));
         Header.Append (16#0A#); --  CRC
         Header.Append (1);
         Append_U32_LE (Header, Unpacked_CRC);
         Header.Append (0);
         Header.Append (0);

         Header.Append (16#05#); --  FilesInfo
         Append_Number (Header, 1);
         Header.Append (16#11#); --  Name
         Name_Field.Append (0);
         Append_Bytes (Name_Field, UTF16LE_NT (Entry_Name));
         Append_Number (Header, Interfaces.Unsigned_64 (Name_Field.Length));
         Header.Append_Vector (Name_Field);
         Append_Bytes (Header, Zlib.Seven_Zip_Properties.Metadata_Image (Metadata));
         Header.Append (0);
         Header.Append (0);

         declare
            Header_Image : constant Byte_Array := To_Byte_Array (Header);
         begin
            Status := Ok;
            return Build_Archive (Header_Image, Packed_Data);
         end;
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Single_File_Archive;

   procedure Append_Filter_Coder
     (Header         : in out Byte_Vectors.Vector;
      Method         : Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;
      Delta_Distance : Positive)
   is
      use type Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;
   begin
      if Method = Zlib.Seven_Zip_Methods.Seven_Zip_Delta_Method then
         Append_Bytes
           (Header, Zlib.Seven_Zip_Coders.Delta_Descriptor_Bytes (Delta_Distance));
      else
         Append_Bytes (Header, Zlib.Seven_Zip_Coders.Descriptor_Bytes (Method));
      end if;
   end Append_Filter_Coder;

   procedure Append_Graph_Coder
     (Header : in out Byte_Vectors.Vector;
      Coder  : Seven_Zip_Graph_Coder)
   is
   begin
      Append_Filter_Coder
        (Header,
         Zlib.Seven_Zip_Methods.Method_For_Graph (Coder.Method),
         Coder.Delta_Distance);
   end Append_Graph_Coder;

   function Filtered_Archive
     (Packed_Data    : Byte_Array;
      Filtered_Data  : Byte_Array;
      Unpacked_Data  : Byte_Array;
      Entry_Name     : String;
      Filter_Method  : Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;
      Codec_Method   : Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;
      Delta_Distance : Positive;
      Metadata       : Seven_Zip_Entry_Metadata;
      Status         : out Status_Code;
      LZMA_Props     : Byte) return Byte_Array
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];
   begin
      Status := Unsupported_Method;

      if Delta_Distance not in 1 .. 256
        or else not Zlib.Seven_Zip_Paths.Entry_Name_Valid (Entry_Name)
      then
         return Empty;
      end if;

      if Metadata.Is_Directory then
         return Header_Only_Entry (Entry_Name, Metadata, Status);
      end if;

      declare
         Packed_CRC   : constant Interfaces.Unsigned_32 := Compute_CRC32 (Packed_Data);
         Unpacked_CRC : constant Interfaces.Unsigned_32 := Compute_CRC32 (Unpacked_Data);
         Header       : Byte_Vectors.Vector;
         Name_Field   : Byte_Vectors.Vector;
      begin
         Header.Append (16#01#); --  Header

         Header.Append (16#04#); --  MainStreamsInfo
         Header.Append (16#06#); --  PackInfo
         Append_Number (Header, 0);
         Append_Number (Header, 1);
         Header.Append (16#09#); --  Size
         Append_Number (Header, Interfaces.Unsigned_64 (Packed_Data'Length));
         Header.Append (16#0A#); --  CRC
         Header.Append (1);
         Append_U32_LE (Header, Packed_CRC);
         Header.Append (0);

         Header.Append (16#07#); --  UnPackInfo
         Header.Append (16#0B#); --  Folder
         Append_Number (Header, 1);
         Header.Append (0);
         Append_Number (Header, 2);
         Append_Bytes
           (Header,
            Zlib.Seven_Zip_Coders.Descriptor_Bytes (Codec_Method, LZMA_Props));
         Append_Filter_Coder (Header, Filter_Method, Delta_Distance);
         Append_Number (Header, 1);
         Append_Number (Header, 0);
         Header.Append (16#0C#); --  CodersUnPackSize
         Append_Number (Header, Interfaces.Unsigned_64 (Filtered_Data'Length));
         Append_Number (Header, Interfaces.Unsigned_64 (Unpacked_Data'Length));
         Header.Append (16#0A#); --  CRC
         Header.Append (1);
         Append_U32_LE (Header, Unpacked_CRC);
         Header.Append (0);
         Header.Append (0);

         Header.Append (16#05#); --  FilesInfo
         Append_Number (Header, 1);
         Header.Append (16#11#); --  Name
         Name_Field.Append (0);
         Append_Bytes (Name_Field, UTF16LE_NT (Entry_Name));
         Append_Number (Header, Interfaces.Unsigned_64 (Name_Field.Length));
         Header.Append_Vector (Name_Field);
         Append_Bytes (Header, Zlib.Seven_Zip_Properties.Metadata_Image (Metadata));
         Header.Append (0);
         Header.Append (0);

         declare
            Header_Image : constant Byte_Array := To_Byte_Array (Header);
         begin
            Status := Ok;
            return Build_Archive (Header_Image, Packed_Data);
         end;
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Filtered_Archive;

   function Method_Graph_Archive
     (Packed_Data    : Byte_Array;
      Entry_Name     : String;
      Coders         : Seven_Zip_Graph_Coder_Array;
      Bind_Pairs     : Seven_Zip_Bind_Pair_Array;
      Packed_Streams : Seven_Zip_Stream_Index_Array;
      Pack_Sizes     : Seven_Zip_Size_Array;
      Unpack_Sizes   : Seven_Zip_Size_Array;
      Unpacked_CRC   : Interfaces.Unsigned_32;
      Metadata       : Seven_Zip_Entry_Metadata;
      Status         : out Status_Code) return Byte_Array
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];

      function Packed_CRC
        (Stream_Index : Positive;
         Start_Offset : Natural) return Interfaces.Unsigned_32
      is
         Size : constant Interfaces.Unsigned_64 := Pack_Sizes (Stream_Index);
      begin
         if Size = 0 then
            return Compute_CRC32 ([1 .. 0 => 0]);
         end if;

         return
           Compute_CRC32
             (Packed_Data
                (Packed_Data'First + Start_Offset ..
                 Packed_Data'First + Start_Offset + Natural (Size) - 1));
      end Packed_CRC;
   begin
      Status := Unsupported_Method;

      if not Zlib.Seven_Zip_Paths.Entry_Name_Valid (Entry_Name) then
         return Empty;
      end if;

      if Metadata.Is_Directory then
         return Header_Only_Entry (Entry_Name, Metadata, Status);
      end if;

      if not Zlib.Seven_Zip_Graphs.Graph_Shape_Valid
        (Coders, Bind_Pairs, Packed_Streams, Pack_Sizes, Unpack_Sizes,
         Packed_Data'Length)
      then
         return Empty;
      end if;

      declare
         Header     : Byte_Vectors.Vector;
         Name_Field : Byte_Vectors.Vector;
      begin
         Header.Append (16#01#); --  Header

         Header.Append (16#04#); --  MainStreamsInfo
         Header.Append (16#06#); --  PackInfo
         Append_Number (Header, 0);
         Append_Number (Header, Interfaces.Unsigned_64 (Pack_Sizes'Length));
         Header.Append (16#09#); --  Size
         for Size of Pack_Sizes loop
            Append_Number (Header, Size);
         end loop;
         Header.Append (16#0A#); --  CRC
         Header.Append (1);
         declare
            Offset : Natural := 0;
         begin
            for I in Pack_Sizes'Range loop
               Append_U32_LE (Header, Packed_CRC (I, Offset));
               Offset := Offset + Natural (Pack_Sizes (I));
            end loop;
         end;
         Header.Append (0);

         Header.Append (16#07#); --  UnPackInfo
         Header.Append (16#0B#); --  Folder
         Append_Number (Header, 1);
         Header.Append (0);
         Append_Number (Header, Interfaces.Unsigned_64 (Coders'Length));
         for Coder of Coders loop
            Append_Graph_Coder (Header, Coder);
         end loop;
         for Pair of Bind_Pairs loop
            Append_Number (Header, Interfaces.Unsigned_64 (Pair.In_Index));
            Append_Number (Header, Interfaces.Unsigned_64 (Pair.Out_Index));
         end loop;
         if Packed_Streams'Length > 1 then
            for Packed_Index of Packed_Streams loop
               Append_Number (Header, Interfaces.Unsigned_64 (Packed_Index));
            end loop;
         end if;
         Header.Append (16#0C#); --  CodersUnPackSize
         for Size of Unpack_Sizes loop
            Append_Number (Header, Size);
         end loop;
         Header.Append (16#0A#); --  CRC
         Header.Append (1);
         Append_U32_LE (Header, Unpacked_CRC);
         Header.Append (0);
         Header.Append (0);

         Header.Append (16#05#); --  FilesInfo
         Append_Number (Header, 1);
         Header.Append (16#11#); --  Name
         Name_Field.Append (0);
         Append_Bytes (Name_Field, UTF16LE_NT (Entry_Name));
         Append_Number (Header, Interfaces.Unsigned_64 (Name_Field.Length));
         Header.Append_Vector (Name_Field);
         Append_Bytes (Header, Zlib.Seven_Zip_Properties.Metadata_Image (Metadata));
         Header.Append (0);
         Header.Append (0);

         declare
            Header_Image : constant Byte_Array := To_Byte_Array (Header);
         begin
            Status := Ok;
            return Build_Archive (Header_Image, Packed_Data);
         end;
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Method_Graph_Archive;

   function Stored_File_List_Archive
     (Payload            : Byte_Array;
      Entry_Names        : Text_Array;
      Sizes              : U64_Array;
      CRCs               : U32_Array;
      Metadata           : Zlib.Seven_Zip_Properties.Entry_Metadata_Array;
      Entry_Is_Directory : Boolean_Array;
      Stream_Count       : Natural;
      Status             : out Status_Code) return Byte_Array
   is
      Empty           : constant Byte_Array (1 .. 0) := [others => 0];
      Empty_File_Bits : constant Boolean_Array (1 .. Entry_Names'Length) :=
        [others => False];
      Header          : Byte_Vectors.Vector;
      Name_Field      : Byte_Vectors.Vector;
      Count           : constant Natural := Entry_Names'Length;
      Payload_CRC     : constant Interfaces.Unsigned_32 := Compute_CRC32 (Payload);
   begin
      Status := Unsupported_Method;

      if Count = 0
        or else Sizes'Length < Stream_Count
        or else CRCs'Length < Stream_Count
        or else Metadata'Length /= Count
        or else Entry_Is_Directory'Length /= Count
      then
         return Empty;
      end if;

      Header.Append (16#01#); --  Header

      if Stream_Count > 0 then
         Header.Append (16#04#); --  MainStreamsInfo
         Header.Append (16#06#); --  PackInfo
         Append_Number (Header, 0);
         Append_Number (Header, 1);
         Header.Append (16#09#); --  Size
         Append_Number (Header, Interfaces.Unsigned_64 (Payload'Length));
         Header.Append (16#0A#); --  CRC
         Header.Append (1);
         Append_U32_LE (Header, Payload_CRC);
         Header.Append (0);

         Header.Append (16#07#); --  UnPackInfo
         Header.Append (16#0B#); --  Folder
         Append_Number (Header, 1);
         Header.Append (0);
         Append_Number (Header, 1);
         Append_Bytes
           (Header,
            Zlib.Seven_Zip_Coders.Descriptor_Bytes
              (Zlib.Seven_Zip_Methods.Seven_Zip_Copy));
         Header.Append (16#0C#); --  CodersUnPackSize
         Append_Number (Header, Interfaces.Unsigned_64 (Payload'Length));
         Header.Append (16#0A#); --  CRC
         Header.Append (1);
         Append_U32_LE (Header, Payload_CRC);
         Header.Append (0);

         Header.Append (16#08#); --  SubStreamsInfo
         Header.Append (16#0D#); --  NumUnPackStream
         Append_Number (Header, Interfaces.Unsigned_64 (Stream_Count));
         if Stream_Count > 1 then
            Header.Append (16#09#); --  Size
            for I in 1 .. Stream_Count - 1 loop
               Append_Number (Header, Sizes (I));
            end loop;
         end if;
         Header.Append (16#0A#); --  CRC
         Header.Append (1);
         for I in 1 .. Stream_Count loop
            Append_U32_LE (Header, CRCs (I));
         end loop;
         Header.Append (0);
         Header.Append (0);
      end if;

      Header.Append (16#05#); --  FilesInfo
      Append_Number (Header, Interfaces.Unsigned_64 (Count));
      Header.Append (16#11#); --  Name
      Name_Field.Append (0);
      for Offset in 0 .. Count - 1 loop
         Append_Bytes
           (Name_Field,
            UTF16LE_NT
              (US.To_String (Entry_Names (Entry_Names'First + Offset))));
      end loop;
      Append_Number (Header, Interfaces.Unsigned_64 (Name_Field.Length));
      Header.Append_Vector (Name_Field);
      if Stream_Count < Count then
         declare
            Bits : Byte_Vectors.Vector;
         begin
            Append_Bytes (Bits, Packed_Bits (Entry_Is_Directory, Count));
            Header.Append (16#0E#); --  EmptyStream
            Append_Number (Header, Interfaces.Unsigned_64 (Bits.Length));
            Header.Append_Vector (Bits);
         end;

         declare
            Bits : Byte_Vectors.Vector;
         begin
            Append_Bytes
              (Bits, Packed_Bits (Empty_File_Bits, Count - Stream_Count));
            Header.Append (16#0F#); --  EmptyFile
            Append_Number (Header, Interfaces.Unsigned_64 (Bits.Length));
            Header.Append_Vector (Bits);
         end;
      end if;
      Append_Bytes (Header, Zlib.Seven_Zip_Properties.Metadata_Image (Metadata));
      Header.Append (0);
      Header.Append (0);

      declare
         Header_Image : constant Byte_Array := To_Byte_Array (Header);
      begin
         Status := Ok;
         return Build_Archive (Header_Image, Payload);
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Stored_File_List_Archive;

   function Compressed_File_List_Archive
     (Payload              : Byte_Array;
      Entry_Names          : Text_Array;
      Method               : Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;
      Pack_Sizes           : U64_Array;
      Pack_CRCs            : U32_Array;
      Unpack_Sizes         : U64_Array;
      Unpack_CRCs          : U32_Array;
      LZMA_Props           : Byte_Array;
      Metadata             : Zlib.Seven_Zip_Properties.Entry_Metadata_Array;
      Entry_Is_Directory   : Boolean_Array;
      Stream_Count         : Natural;
      Solid                : Boolean;
      Encrypt              : Boolean;
      Solid_Compressed_Len : Natural;
      AES_IV               : Byte_Array;
      Status               : out Status_Code) return Byte_Array
   is
      Empty           : constant Byte_Array (1 .. 0) := [others => 0];
      Empty_File_Bits : constant Boolean_Array (1 .. Entry_Names'Length) :=
        [others => False];
      Header          : Byte_Vectors.Vector;
      Name_Field      : Byte_Vectors.Vector;
      Count           : constant Natural := Entry_Names'Length;
      Total_Unpack_Size : Interfaces.Unsigned_64 := 0;
   begin
      Status := Unsupported_Method;

      if Count = 0
        or else Pack_Sizes'Length < Natural'Max (1, Stream_Count)
        or else Pack_CRCs'Length < Stream_Count
        or else Unpack_Sizes'Length < Stream_Count
        or else Unpack_CRCs'Length < Stream_Count
        or else LZMA_Props'Length < Natural'Max (1, Stream_Count)
        or else Metadata'Length /= Count
        or else Entry_Is_Directory'Length /= Count
        or else (Encrypt and then AES_IV'Length /= 16)
      then
         return Empty;
      end if;

      for I in 1 .. Stream_Count loop
         Total_Unpack_Size := Total_Unpack_Size + Unpack_Sizes (I);
      end loop;

      Header.Append (16#01#); --  Header

      if Stream_Count > 0 and then Solid then
         Header.Append (16#04#); --  MainStreamsInfo
         Header.Append (16#06#); --  PackInfo
         Append_Number (Header, 0);
         Append_Number (Header, 1);
         Header.Append (16#09#); --  Size
         Append_Number (Header, Pack_Sizes (1));
         Header.Append (0);      --  end PackInfo

         Header.Append (16#07#); --  UnPackInfo
         Header.Append (16#0B#); --  Folder
         Append_Number (Header, 1);  --  one folder
         Header.Append (0);          --  external
         if Encrypt then
            Append_Number (Header, 2);  --  AES + inner coder
            Append_Bytes (Header, Zlib.Seven_Zip_Coders.AES_Descriptor_Bytes (AES_IV));
            Append_Bytes
              (Header,
               Zlib.Seven_Zip_Coders.Descriptor_Bytes (Method, LZMA_Props (1)));
            Append_Number (Header, 1);  --  bind In=1 (inner.in)
            Append_Number (Header, 0);  --  bind Out=0 (AES.out)
            Header.Append (16#0C#); --  CodersUnPackSize
            Append_Number
              (Header, Interfaces.Unsigned_64 (Solid_Compressed_Len));
            Append_Number (Header, Total_Unpack_Size);
         else
            Append_Number (Header, 1);  --  one coder
            Append_Bytes
              (Header,
               Zlib.Seven_Zip_Coders.Descriptor_Bytes (Method, LZMA_Props (1)));
            Header.Append (16#0C#); --  CodersUnPackSize
            Append_Number (Header, Total_Unpack_Size);
         end if;
         Header.Append (0);      --  end UnPackInfo (no folder CRC)

         Header.Append (16#08#); --  SubStreamsInfo
         Header.Append (16#0D#); --  NumUnPackStream
         Append_Number (Header, Interfaces.Unsigned_64 (Stream_Count));
         if Stream_Count > 1 then
            Header.Append (16#09#); --  Size (all but last substream)
            for I in 1 .. Stream_Count - 1 loop
               Append_Number (Header, Unpack_Sizes (I));
            end loop;
         end if;
         Header.Append (16#0A#); --  CRC
         Header.Append (1);
         for I in 1 .. Stream_Count loop
            Append_U32_LE (Header, Unpack_CRCs (I));
         end loop;
         Header.Append (0);      --  end SubStreamsInfo
         Header.Append (0);      --  end MainStreamsInfo
      elsif Stream_Count > 0 then
         Header.Append (16#04#); --  MainStreamsInfo
         Header.Append (16#06#); --  PackInfo
         Append_Number (Header, 0);
         Append_Number (Header, Interfaces.Unsigned_64 (Stream_Count));
         Header.Append (16#09#); --  Size
         for I in 1 .. Stream_Count loop
            Append_Number (Header, Pack_Sizes (I));
         end loop;
         Header.Append (16#0A#); --  CRC
         Header.Append (1);
         for I in 1 .. Stream_Count loop
            Append_U32_LE (Header, Pack_CRCs (I));
         end loop;
         Header.Append (0);

         Header.Append (16#07#); --  UnPackInfo
         Header.Append (16#0B#); --  Folder
         Append_Number (Header, Interfaces.Unsigned_64 (Stream_Count));
         Header.Append (0);
         for I in 1 .. Stream_Count loop
            Append_Number (Header, 1);
            Append_Bytes
              (Header,
               Zlib.Seven_Zip_Coders.Descriptor_Bytes (Method, LZMA_Props (I)));
         end loop;
         Header.Append (16#0C#); --  CodersUnPackSize
         for I in 1 .. Stream_Count loop
            Append_Number (Header, Unpack_Sizes (I));
         end loop;
         Header.Append (16#0A#); --  CRC
         Header.Append (1);
         for I in 1 .. Stream_Count loop
            Append_U32_LE (Header, Unpack_CRCs (I));
         end loop;
         Header.Append (0);
         Header.Append (0);
      end if;

      Header.Append (16#05#); --  FilesInfo
      Append_Number (Header, Interfaces.Unsigned_64 (Count));
      Header.Append (16#11#); --  Name
      Name_Field.Append (0);
      for Offset in 0 .. Count - 1 loop
         Append_Bytes
           (Name_Field,
            UTF16LE_NT
              (US.To_String (Entry_Names (Entry_Names'First + Offset))));
      end loop;
      Append_Number (Header, Interfaces.Unsigned_64 (Name_Field.Length));
      Header.Append_Vector (Name_Field);
      if Stream_Count < Count then
         declare
            Bits : Byte_Vectors.Vector;
         begin
            Append_Bytes (Bits, Packed_Bits (Entry_Is_Directory, Count));
            Header.Append (16#0E#); --  EmptyStream
            Append_Number (Header, Interfaces.Unsigned_64 (Bits.Length));
            Header.Append_Vector (Bits);
         end;

         declare
            Bits : Byte_Vectors.Vector;
         begin
            Append_Bytes
              (Bits, Packed_Bits (Empty_File_Bits, Count - Stream_Count));
            Header.Append (16#0F#); --  EmptyFile
            Append_Number (Header, Interfaces.Unsigned_64 (Bits.Length));
            Header.Append_Vector (Bits);
         end;
      end if;
      Append_Bytes (Header, Zlib.Seven_Zip_Properties.Metadata_Image (Metadata));
      Header.Append (0);
      Header.Append (0);

      declare
         Header_Image : constant Byte_Array := To_Byte_Array (Header);
      begin
         Status := Ok;
         return Build_Archive (Header_Image, Payload);
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Compressed_File_List_Archive;

   function AES_LZMA_Archive
     (Packed_Data     : Byte_Array;
      Entry_Name      : String;
      Compressed_Size : Natural;
      Plain_Size      : Natural;
      Plain_CRC       : Interfaces.Unsigned_32;
      IV              : Byte_Array;
      LZMA_Props      : Byte;
      Status          : out Status_Code) return Byte_Array
   is
      Empty      : constant Byte_Array (1 .. 0) := [others => 0];
      Header     : Byte_Vectors.Vector;
      Name_Field : Byte_Vectors.Vector;
   begin
      Status := Unsupported_Method;

      if Packed_Data'Length = 0
        or else IV'Length /= 16
        or else not Zlib.Seven_Zip_Paths.Entry_Name_Valid (Entry_Name)
      then
         return Empty;
      end if;

      Header.Append (16#01#);
      Header.Append (16#04#); --  MainStreamsInfo
      Header.Append (16#06#); --  PackInfo
      Append_Number (Header, 0);
      Append_Number (Header, 1);
      Header.Append (16#09#); --  Size
      Append_Number (Header, Interfaces.Unsigned_64 (Packed_Data'Length));
      Header.Append (0);      --  end PackInfo

      Header.Append (16#07#); --  UnPackInfo
      Header.Append (16#0B#); --  Folder
      Append_Number (Header, 1);  --  one folder
      Header.Append (0);          --  external
      Append_Number (Header, 2);  --  two coders
      Append_Bytes (Header, Zlib.Seven_Zip_Coders.AES_Descriptor_Bytes (IV));
      Append_Bytes
        (Header,
         Zlib.Seven_Zip_Coders.Descriptor_Bytes
           (Zlib.Seven_Zip_Methods.Seven_Zip_LZMA_Method, LZMA_Props));
      Append_Number (Header, 1);
      Append_Number (Header, 0);
      Header.Append (16#0C#); --  CodersUnPackSize
      Append_Number (Header, Interfaces.Unsigned_64 (Compressed_Size));
      Append_Number (Header, Interfaces.Unsigned_64 (Plain_Size));
      Header.Append (0);      --  end UnPackInfo

      Header.Append (16#08#); --  SubStreamsInfo
      Header.Append (16#0A#); --  CRC
      Header.Append (1);
      Append_U32_LE (Header, Plain_CRC);
      Header.Append (0);      --  end SubStreamsInfo
      Header.Append (0);      --  end MainStreamsInfo

      Header.Append (16#05#); --  FilesInfo
      Append_Number (Header, 1);
      Header.Append (16#11#); --  Name
      Name_Field.Append (0);
      Append_Bytes (Name_Field, UTF16LE_NT (Entry_Name));
      Append_Number (Header, Interfaces.Unsigned_64 (Name_Field.Length));
      Header.Append_Vector (Name_Field);
      Header.Append (0);
      Header.Append (0);

      declare
         Header_Image : constant Byte_Array := To_Byte_Array (Header);
      begin
         Status := Ok;
         return Build_Archive (Header_Image, Packed_Data);
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end AES_LZMA_Archive;

   function BCJ2_Archive
     (Streams    : Zlib.Seven_Zip_Filters.BCJ2_Encoded_Streams;
      Entry_Name : String;
      Plain_Size : Natural;
      Plain_CRC  : Interfaces.Unsigned_32;
      Status     : out Status_Code) return Byte_Array
   is
      Empty      : constant Byte_Array (1 .. 0) := [others => 0];
      Header     : Byte_Vectors.Vector;
      Name_Field : Byte_Vectors.Vector;
   begin
      Status := Unsupported_Method;

      if not Zlib.Seven_Zip_Paths.Entry_Name_Valid (Entry_Name) then
         return Empty;
      end if;

      Header.Append (16#01#);
      Header.Append (16#04#); --  MainStreamsInfo
      Header.Append (16#06#); --  PackInfo
      Append_Number (Header, 0);
      Append_Number (Header, 4);
      Header.Append (16#09#); --  Size
      Append_Number (Header, Interfaces.Unsigned_64 (Streams.Main_Stream'Length));
      Append_Number (Header, Interfaces.Unsigned_64 (Streams.Call_Stream'Length));
      Append_Number (Header, Interfaces.Unsigned_64 (Streams.Jump_Stream'Length));
      Append_Number (Header, Interfaces.Unsigned_64 (Streams.RC_Stream'Length));
      Header.Append (16#00#); --  end PackInfo

      Header.Append (16#07#); --  UnPackInfo
      Header.Append (16#0B#); --  Folder
      Append_Number (Header, 1);
      Header.Append (16#00#);
      Append_Number (Header, 1);
      Append_Bytes
        (Header,
         Zlib.Seven_Zip_Coders.Descriptor_Bytes
           (Zlib.Seven_Zip_Methods.Seven_Zip_BCJ2_Method));
      Append_Number (Header, 0);
      Append_Number (Header, 1);
      Append_Number (Header, 2);
      Append_Number (Header, 3);
      Header.Append (16#0C#); --  CodersUnPackSize
      Append_Number (Header, Interfaces.Unsigned_64 (Plain_Size));
      Header.Append (16#00#); --  end UnPackInfo

      Header.Append (16#08#); --  SubStreamsInfo
      Header.Append (16#0A#); --  CRC
      Header.Append (1);
      Append_U32_LE (Header, Plain_CRC);
      Header.Append (16#00#); --  end SubStreamsInfo
      Header.Append (16#00#); --  end MainStreamsInfo

      Header.Append (16#05#); --  FilesInfo
      Append_Number (Header, 1);
      Header.Append (16#11#); --  Name
      Name_Field.Append (0);
      Append_Bytes (Name_Field, UTF16LE_NT (Entry_Name));
      Append_Number (Header, Interfaces.Unsigned_64 (Name_Field.Length));
      Header.Append_Vector (Name_Field);
      Header.Append (16#00#);
      Header.Append (16#00#);

      declare
         Pack_Len : constant Natural :=
           Streams.Main_Stream'Length
           + Streams.Call_Stream'Length
           + Streams.Jump_Stream'Length
           + Streams.RC_Stream'Length;
         Header_Image : constant Byte_Array := To_Byte_Array (Header);
         Payload      : Byte_Array (1 .. Pack_Len);
         Payload_Pos  : Natural := Payload'First;
      begin
         Payload
           (Payload_Pos .. Payload_Pos + Streams.Main_Stream'Length - 1) :=
           Streams.Main_Stream;
         Payload_Pos := Payload_Pos + Streams.Main_Stream'Length;
         Payload
           (Payload_Pos .. Payload_Pos + Streams.Call_Stream'Length - 1) :=
           Streams.Call_Stream;
         Payload_Pos := Payload_Pos + Streams.Call_Stream'Length;
         Payload
           (Payload_Pos .. Payload_Pos + Streams.Jump_Stream'Length - 1) :=
           Streams.Jump_Stream;
         Payload_Pos := Payload_Pos + Streams.Jump_Stream'Length;
         Payload
           (Payload_Pos .. Payload_Pos + Streams.RC_Stream'Length - 1) :=
           Streams.RC_Stream;

         Status := Ok;
         return Build_Archive (Header_Image, Payload);
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end BCJ2_Archive;

   function AES_LZMA_Encoded_Header
     (Pack_Offset     : Interfaces.Unsigned_64;
      Encrypted_Size  : Interfaces.Unsigned_64;
      Compressed_Size : Interfaces.Unsigned_64;
      Plain_Size      : Interfaces.Unsigned_64;
      IV              : Byte_Array;
      LZMA_Props      : Byte) return Byte_Array
   is
      use Zlib.Seven_Zip_Methods;

      Header : Byte_Vectors.Vector;
   begin
      Header.Append (16#17#); --  kEncodedHeader
      Header.Append (16#06#); --  PackInfo
      Append_Number (Header, Pack_Offset);
      Append_Number (Header, 1);
      Header.Append (16#09#); --  Size
      Append_Number (Header, Encrypted_Size);
      Header.Append (16#00#); --  end PackInfo

      Header.Append (16#07#); --  UnPackInfo
      Header.Append (16#0B#); --  Folder
      Append_Number (Header, 1);
      Header.Append (16#00#); --  external
      Append_Number (Header, 2);
      Append_Bytes (Header, Zlib.Seven_Zip_Coders.AES_Descriptor_Bytes (IV));
      Append_Bytes
        (Header,
         Zlib.Seven_Zip_Coders.Descriptor_Bytes
           (Seven_Zip_LZMA_Method, LZMA_Props));
      Append_Number (Header, 1); --  bind In=1 (LZMA.in)
      Append_Number (Header, 0); --  bind Out=0 (AES.out)
      Header.Append (16#0C#); --  CodersUnPackSize
      Append_Number (Header, Compressed_Size);
      Append_Number (Header, Plain_Size);
      Header.Append (16#00#); --  end UnPackInfo
      Header.Append (16#00#); --  end StreamsInfo

      return To_Byte_Array (Header);
   end AES_LZMA_Encoded_Header;

   function Encrypted_Header_Archive
     (Main_Pack         : Byte_Array;
      Encrypted_Header  : Byte_Array;
      Compressed_Size   : Natural;
      Plain_Header_Size : Natural;
      IV                : Byte_Array;
      LZMA_Props        : Byte;
      Status            : out Status_Code) return Byte_Array
   is
      Empty : constant Byte_Array (1 .. 0) := [others => 0];
   begin
      Status := Unsupported_Method;

      if Encrypted_Header'Length = 0 or else IV'Length /= 16 then
         return Empty;
      end if;

      declare
         ESI_Image : constant Byte_Array :=
           AES_LZMA_Encoded_Header
             (Pack_Offset     => Interfaces.Unsigned_64 (Main_Pack'Length),
              Encrypted_Size  => Interfaces.Unsigned_64 (Encrypted_Header'Length),
              Compressed_Size => Interfaces.Unsigned_64 (Compressed_Size),
              Plain_Size      => Interfaces.Unsigned_64 (Plain_Header_Size),
              IV              => IV,
              LZMA_Props      => LZMA_Props);
         Payload     : Byte_Array
           (1 .. Main_Pack'Length + Encrypted_Header'Length);
         Payload_Pos : Natural := Payload'First;
      begin
         Payload (Payload_Pos .. Payload_Pos + Main_Pack'Length - 1) :=
           Main_Pack;
         Payload_Pos := Payload_Pos + Main_Pack'Length;
         Payload (Payload_Pos .. Payload_Pos + Encrypted_Header'Length - 1) :=
           Encrypted_Header;

         Status := Ok;
         return Build_Archive (ESI_Image, Payload);
      end;
   exception
      when others =>
         Status := Unsupported_Method;
         return Empty;
   end Encrypted_Header_Archive;

end Zlib.Seven_Zip_Container;
