with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with CryptoLib.Checksums;
with Interfaces;

package body Zlib.ZIP_Streaming_Extraction is

   package SIO renames Ada.Streams.Stream_IO;
   package US renames Ada.Strings.Unbounded;
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;

   --  A ZIP end-of-central-directory record is 22 bytes plus a comment of at
   --  most 65535 bytes, and a ZIP64 locator adds 20 bytes ahead of it.
   Tail_Window : constant := 22 + 65_535 + 20;

   Chunk_Size  : constant := 64 * 1024;

   Central_Signature : constant Interfaces.Unsigned_32 := 16#0201_4B50#;
   Local_Signature   : constant Interfaces.Unsigned_32 := 16#0403_4B50#;
   EOCD_Signature    : constant Interfaces.Unsigned_32 := 16#0605_4B50#;
   Locator_Signature : constant Interfaces.Unsigned_32 := 16#0706_4B50#;
   Z64_EOCD_Signature : constant Interfaces.Unsigned_32 := 16#0606_4B50#;

   Method_Stored  : constant Interfaces.Unsigned_16 := 0;
   Method_Deflate : constant Interfaces.Unsigned_16 := 8;

   ---------------------------------------------------------------------------
   --  Little-endian field readers over an in-memory window. These mirror the
   --  root body's ZIP_U*_At helpers, which are not visible to a child package.
   ---------------------------------------------------------------------------

   function U16_At
     (Data : Byte_Array; Pos : Natural) return Interfaces.Unsigned_16
   is
   begin
      return Interfaces.Unsigned_16 (Data (Pos))
        or Interfaces.Shift_Left (Interfaces.Unsigned_16 (Data (Pos + 1)), 8);
   end U16_At;

   function U32_At
     (Data : Byte_Array; Pos : Natural) return Interfaces.Unsigned_32
   is
      Result : Interfaces.Unsigned_32 := 0;
   begin
      for Offset in reverse 0 .. 3 loop
         Result := Interfaces.Shift_Left (Result, 8)
           or Interfaces.Unsigned_32 (Data (Pos + Offset));
      end loop;
      return Result;
   end U32_At;

   function U64_At
     (Data : Byte_Array; Pos : Natural) return Interfaces.Unsigned_64
   is
      Result : Interfaces.Unsigned_64 := 0;
   begin
      for Offset in reverse 0 .. 7 loop
         Result := Interfaces.Shift_Left (Result, 8)
           or Interfaces.Unsigned_64 (Data (Pos + Offset));
      end loop;
      return Result;
   end U64_At;

   ---------------------------------------------------------------------------
   --  Little-endian field writers, for rebuilding one member as its own image.
   ---------------------------------------------------------------------------

   procedure Put_U16
     (Data : in out Byte_Array; Pos : Natural; Value : Interfaces.Unsigned_16)
   is
   begin
      Data (Pos) := Byte (Value and 16#FF#);
      Data (Pos + 1) := Byte (Interfaces.Shift_Right (Value, 8) and 16#FF#);
   end Put_U16;

   procedure Put_U32
     (Data : in out Byte_Array; Pos : Natural; Value : Interfaces.Unsigned_32)
   is
   begin
      for Offset in 0 .. 3 loop
         Data (Pos + Offset) :=
           Byte (Interfaces.Shift_Right (Value, 8 * Offset) and 16#FF#);
      end loop;
   end Put_U32;

   procedure Put_Name (Data : in out Byte_Array; Pos : Natural; Name : String)
   is
   begin
      for I in Name'Range loop
         Data (Pos + (I - Name'First)) := Byte (Character'Pos (Name (I)));
      end loop;
   end Put_Name;

   --  Wrap one member's compressed bytes in a minimal single-entry ZIP so the
   --  codec bridge, which works on whole images, can decode it without the
   --  original archive being in memory. Mirrors the synthetic image built by
   --  ZIP_Traditional_Decrypted_External_Image in the root body.
   function Single_Entry_Image
     (Entry_Name : String;
      Flags      : Interfaces.Unsigned_16;
      Method     : Interfaces.Unsigned_16;
      CRC        : Interfaces.Unsigned_32;
      Payload    : Byte_Array;
      Plain_Size : Interfaces.Unsigned_32) return Byte_Array
   is
      Name_Len       : constant Natural := Entry_Name'Length;
      Payload_Len    : constant Natural := Payload'Length;
      Central_Offset : constant Natural := 30 + Name_Len + Payload_Len;
      Central_Size   : constant Natural := 46 + Name_Len;
      EOCD_Offset    : constant Natural := Central_Offset + Central_Size;
      Image          : Byte_Array (1 .. EOCD_Offset + 22) := [others => 0];
   begin
      Put_U32 (Image, 1, 16#0403_4B50#);
      Put_U16 (Image, 5, 20);
      --  The encryption flag has to survive into the rebuilt entry, or the
      --  bridge has no way to know the payload needs decrypting.
      Put_U16 (Image, 7, Flags);
      Put_U16 (Image, 9, Method);
      Put_U32 (Image, 15, CRC);
      Put_U32 (Image, 19, Interfaces.Unsigned_32 (Payload_Len));
      Put_U32 (Image, 23, Plain_Size);
      Put_U16 (Image, 27, Interfaces.Unsigned_16 (Name_Len));
      Put_Name (Image, 31, Entry_Name);
      for I in 1 .. Payload_Len loop
         Image (30 + Name_Len + I) := Payload (Payload'First + I - 1);
      end loop;

      Put_U32 (Image, Central_Offset + 1, 16#0201_4B50#);
      Put_U16 (Image, Central_Offset + 5, 20);
      Put_U16 (Image, Central_Offset + 7, 20);
      Put_U16 (Image, Central_Offset + 9, Flags);
      Put_U16 (Image, Central_Offset + 11, Method);
      Put_U32 (Image, Central_Offset + 17, CRC);
      Put_U32 (Image, Central_Offset + 21, Interfaces.Unsigned_32 (Payload_Len));
      Put_U32 (Image, Central_Offset + 25, Plain_Size);
      Put_U16 (Image, Central_Offset + 29, Interfaces.Unsigned_16 (Name_Len));
      Put_U32 (Image, Central_Offset + 43, 0);
      Put_Name (Image, Central_Offset + 47, Entry_Name);

      Put_U32 (Image, EOCD_Offset + 1, 16#0605_4B50#);
      Put_U16 (Image, EOCD_Offset + 9, 1);
      Put_U16 (Image, EOCD_Offset + 11, 1);
      Put_U32 (Image, EOCD_Offset + 13, Interfaces.Unsigned_32 (Central_Size));
      Put_U32 (Image, EOCD_Offset + 17, Interfaces.Unsigned_32 (Central_Offset));
      return Image;
   end Single_Entry_Image;

   ---------------------------------------------------------------------------
   --  Positioned reads. Stream_IO indices are 1-based; ZIP offsets are 0-based.
   ---------------------------------------------------------------------------

   procedure Read_At
     (File   : in out SIO.File_Type;
      Offset : Interfaces.Unsigned_64;
      Into   : out Byte_Array;
      Ok     : out Boolean)
   is
      Buffer : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Into'Length));
      Last   : Ada.Streams.Stream_Element_Offset;
   begin
      Into := [others => 0];
      Ok := False;

      if Into'Length = 0 then
         Ok := True;
         return;
      end if;

      SIO.Set_Index (File, SIO.Positive_Count (Offset + 1));
      SIO.Read (File, Buffer, Last);
      if Last /= Buffer'Last then
         return;
      end if;

      declare
         Target : Natural := Into'First;
      begin
         for I in Buffer'Range loop
            Into (Target) := Byte (Buffer (I));
            Target := Target + 1;
         end loop;
      end;
      Ok := True;
   end Read_At;

   ---------------------------------------------------------------------------
   --  Central directory location.
   ---------------------------------------------------------------------------

   --  Scan the tail window backwards for the EOCD record and follow the ZIP64
   --  locator when the 32-bit fields are escaped. Offsets returned are
   --  absolute byte offsets into the archive file.
   procedure Find_Central_Directory
     (File      : in out SIO.File_Type;
      File_Size : Interfaces.Unsigned_64;
      CD_Offset : out Interfaces.Unsigned_64;
      CD_Size   : out Interfaces.Unsigned_64;
      CD_Count  : out Natural;
      Found     : out Boolean)
   is
      Window_Length : constant Interfaces.Unsigned_64 :=
        Interfaces.Unsigned_64'Min (File_Size, Tail_Window);
      Window_Start  : constant Interfaces.Unsigned_64 :=
        File_Size - Window_Length;
      Window        : Byte_Array (0 .. Natural (Window_Length) - 1);
      Read_Ok       : Boolean;
   begin
      CD_Offset := 0;
      CD_Size := 0;
      CD_Count := 0;
      Found := False;

      if File_Size < 22 then
         return;
      end if;

      Read_At (File, Window_Start, Window, Read_Ok);
      if not Read_Ok then
         return;
      end if;

      for P in reverse Window'First .. Window'Last - 21 loop
         if U32_At (Window, P) = EOCD_Signature then
            declare
               Count16 : constant Interfaces.Unsigned_16 := U16_At (Window, P + 10);
               Size32  : constant Interfaces.Unsigned_32 := U32_At (Window, P + 12);
               Off32   : constant Interfaces.Unsigned_32 := U32_At (Window, P + 16);
            begin
               if (Count16 = 16#FFFF#
                   or else Off32 = 16#FFFF_FFFF#
                   or else Size32 = 16#FFFF_FFFF#)
                 and then P - 20 >= Window'First
                 and then U32_At (Window, P - 20) = Locator_Signature
               then
                  declare
                     Z64_Offset : constant Interfaces.Unsigned_64 :=
                       U64_At (Window, P - 20 + 8);
                     Header     : Byte_Array (0 .. 55);
                     Header_Ok  : Boolean;
                  begin
                     if Z64_Offset + 56 <= File_Size then
                        Read_At (File, Z64_Offset, Header, Header_Ok);
                        if Header_Ok
                          and then U32_At (Header, 0) = Z64_EOCD_Signature
                        then
                           CD_Count := Natural (U64_At (Header, 32));
                           CD_Size := U64_At (Header, 40);
                           CD_Offset := U64_At (Header, 48);
                           Found := CD_Offset + CD_Size <= File_Size;
                           return;
                        end if;
                     end if;
                  end;
               end if;

               CD_Count := Natural (Count16);
               CD_Size := Interfaces.Unsigned_64 (Size32);
               CD_Offset := Interfaces.Unsigned_64 (Off32);
               Found := CD_Offset + CD_Size <= File_Size;
               return;
            end;
         end if;
      end loop;
   end Find_Central_Directory;

   ---------------------------------------------------------------------------
   --  ZIP64 extra-field resolution for one central-directory record.
   ---------------------------------------------------------------------------

   procedure Resolve_Sizes
     (Central    : Byte_Array;
      Extra_First : Natural;
      Extra_Len  : Natural;
      Comp_32    : Interfaces.Unsigned_32;
      Unc_32     : Interfaces.Unsigned_32;
      Off_32     : Interfaces.Unsigned_32;
      Comp       : out Interfaces.Unsigned_64;
      Unc        : out Interfaces.Unsigned_64;
      Offset     : out Interfaces.Unsigned_64)
   is
      Pos : Natural := Extra_First;
   begin
      Comp := Interfaces.Unsigned_64 (Comp_32);
      Unc := Interfaces.Unsigned_64 (Unc_32);
      Offset := Interfaces.Unsigned_64 (Off_32);

      while Pos + 3 <= Extra_First + Extra_Len - 1 loop
         declare
            Tag       : constant Interfaces.Unsigned_16 := U16_At (Central, Pos);
            Data_Size : constant Natural :=
              Natural (U16_At (Central, Pos + 2));
            Field     : Natural := Pos + 4;
         begin
            exit when Field + Data_Size > Extra_First + Extra_Len;

            if Tag = 16#0001# then
               if Unc_32 = 16#FFFF_FFFF# and then Field + 7 < Field + Data_Size then
                  Unc := U64_At (Central, Field);
                  Field := Field + 8;
               end if;
               if Comp_32 = 16#FFFF_FFFF#
                 and then Field + 8 <= Pos + 4 + Data_Size
               then
                  Comp := U64_At (Central, Field);
                  Field := Field + 8;
               end if;
               if Off_32 = 16#FFFF_FFFF#
                 and then Field + 8 <= Pos + 4 + Data_Size
               then
                  Offset := U64_At (Central, Field);
               end if;
               return;
            end if;

            Pos := Pos + 4 + Data_Size;
         end;
      end loop;
   end Resolve_Sizes;

   ---------------------------------------------------------------------------
   --  Stream one member from the archive file to its output file.
   ---------------------------------------------------------------------------

   procedure Extract_Member
     (File        : in out SIO.File_Type;
      File_Size   : Interfaces.Unsigned_64;
      Local_Offset : Interfaces.Unsigned_64;
      Method      : Interfaces.Unsigned_16;
      Comp_Size   : Interfaces.Unsigned_64;
      Unc_Size    : Interfaces.Unsigned_64;
      Expected_CRC : Interfaces.Unsigned_32;
      Target_Path : String;
      Status      : out Status_Code)
   is
      Header     : Byte_Array (0 .. 29);
      Header_Ok  : Boolean;
      Data_Start : Interfaces.Unsigned_64;
      Remaining  : Interfaces.Unsigned_64;
      Produced   : Interfaces.Unsigned_64 := 0;
      CRC        : CryptoLib.Checksums.CRC32_State;
      Output     : SIO.File_Type;
      Opened     : Boolean := False;
      Filter     : Zlib.Filter_Type;
      Inflating  : Boolean := False;
   begin
      Status := Ok;
      CryptoLib.Checksums.CRC32_Reset (CRC);

      if Local_Offset + 30 > File_Size then
         Status := Unexpected_End_Of_Input;
         return;
      end if;

      Read_At (File, Local_Offset, Header, Header_Ok);
      if not Header_Ok or else U32_At (Header, 0) /= Local_Signature then
         Status := Unexpected_End_Of_Input;
         return;
      end if;

      --  The local header repeats the name and extra fields with their own
      --  lengths; only the lengths matter here, because the central directory
      --  already supplied the authoritative name and sizes.
      Data_Start := Local_Offset + 30
        + Interfaces.Unsigned_64 (U16_At (Header, 26))
        + Interfaces.Unsigned_64 (U16_At (Header, 28));

      if Data_Start + Comp_Size > File_Size then
         Status := Unexpected_End_Of_Input;
         return;
      end if;

      SIO.Create (Output, SIO.Out_File, Target_Path);
      Opened := True;

      if Method = Method_Deflate then
         Zlib.Inflate_Init (Filter, Zlib.Raw_Deflate);
         Inflating := True;
      end if;

      Remaining := Comp_Size;

      while Remaining > 0 loop
         declare
            Want : constant Natural :=
              Natural (Interfaces.Unsigned_64'Min (Remaining, Chunk_Size));
            In_Bytes : Byte_Array (0 .. Want - 1);
            Read_Ok  : Boolean;
         begin
            Read_At (File, Data_Start + (Comp_Size - Remaining), In_Bytes, Read_Ok);
            if not Read_Ok then
               Status := Unexpected_End_Of_Input;
               exit;
            end if;
            Remaining := Remaining - Interfaces.Unsigned_64 (Want);

            if Method = Method_Stored then
               declare
                  Out_Bytes : Ada.Streams.Stream_Element_Array
                    (1 .. Ada.Streams.Stream_Element_Offset (Want));
                  Target    : Ada.Streams.Stream_Element_Offset := 1;
               begin
                  for B of In_Bytes loop
                     CryptoLib.Checksums.CRC32_Update
                       (CRC, Ada.Streams.Stream_Element (B));
                     Out_Bytes (Target) := Ada.Streams.Stream_Element (B);
                     Target := Target + 1;
                  end loop;
                  SIO.Write (Output, Out_Bytes);
                  Produced := Produced + Interfaces.Unsigned_64 (Want);
               end;
            else
               declare
                  In_Stream : Ada.Streams.Stream_Element_Array
                    (1 .. Ada.Streams.Stream_Element_Offset (Want));
                  Target    : Ada.Streams.Stream_Element_Offset := 1;
                  Consumed  : Ada.Streams.Stream_Element_Offset;
                  In_First  : Ada.Streams.Stream_Element_Offset := 1;
               begin
                  for B of In_Bytes loop
                     In_Stream (Target) := Ada.Streams.Stream_Element (B);
                     Target := Target + 1;
                  end loop;

                  --  Translate consumes as much as is useful per call, so keep
                  --  feeding the same chunk until it is fully absorbed.
                  loop
                     declare
                        Out_Stream : Ada.Streams.Stream_Element_Array
                          (1 .. Chunk_Size);
                        Out_Last   : Ada.Streams.Stream_Element_Offset;
                     begin
                        Zlib.Translate
                          (Filter   => Filter,
                           In_Data  => In_Stream (In_First .. In_Stream'Last),
                           In_Last  => Consumed,
                           Out_Data => Out_Stream,
                           Out_Last => Out_Last,
                           Flush    => Zlib.No_Flush);

                        if Out_Last >= Out_Stream'First then
                           for I in Out_Stream'First .. Out_Last loop
                              CryptoLib.Checksums.CRC32_Update
                                (CRC, Out_Stream (I));
                           end loop;
                           SIO.Write
                             (Output, Out_Stream (Out_Stream'First .. Out_Last));
                           Produced := Produced
                             + Interfaces.Unsigned_64 (Out_Last - Out_Stream'First + 1);
                        end if;

                        exit when Consumed >= In_Stream'Last;
                        exit when Consumed < In_First
                          and then Out_Last < Out_Stream'First;
                        In_First := Consumed + 1;
                     end;
                  end loop;
               end;
            end if;
         end;
      end loop;

      --  Drain whatever the decoder still holds once the input is exhausted.
      if Status = Ok and then Inflating then
         loop
            declare
               Out_Stream : Ada.Streams.Stream_Element_Array (1 .. Chunk_Size);
               Out_Last   : Ada.Streams.Stream_Element_Offset;
            begin
               Zlib.Flush (Filter, Out_Stream, Out_Last, Zlib.No_Flush);
               exit when Out_Last < Out_Stream'First;
               for I in Out_Stream'First .. Out_Last loop
                  CryptoLib.Checksums.CRC32_Update (CRC, Out_Stream (I));
               end loop;
               SIO.Write (Output, Out_Stream (Out_Stream'First .. Out_Last));
               Produced := Produced
                 + Interfaces.Unsigned_64 (Out_Last - Out_Stream'First + 1);
            end;
         end loop;
      end if;

      if Inflating then
         Zlib.Close (Filter, Ignore_Error => True);
         Inflating := False;
      end if;

      SIO.Close (Output);
      Opened := False;

      if Status = Ok then
         if Produced /= Unc_Size then
            Status := Unexpected_End_Of_Input;
         elsif CryptoLib.Checksums.CRC32_Value (CRC) /= Expected_CRC then
            Status := Invalid_Checksum;
         end if;
      end if;

   exception
      when Storage_Error =>
         if Inflating then
            Zlib.Close (Filter, Ignore_Error => True);
         end if;
         if Opened then
            SIO.Close (Output);
         end if;
         Status := Insufficient_Memory;

      when others =>
         if Inflating then
            Zlib.Close (Filter, Ignore_Error => True);
         end if;
         if Opened then
            SIO.Close (Output);
         end if;
         --  Streaming inflate signals invalid or truncated data by exception;
         --  this is a status-returning API, so map it rather than propagate.
         Status := Unexpected_End_Of_Input;
   end Extract_Member;

   --  A member this package cannot stream is rebuilt as a single-entry image
   --  holding only its own compressed bytes and handed to the codec bridge, so
   --  the cost is that member rather than the whole archive.
   procedure Extract_Foreign_Member
     (File         : in out SIO.File_Type;
      File_Size    : Interfaces.Unsigned_64;
      Local_Offset : Interfaces.Unsigned_64;
      Method       : Interfaces.Unsigned_16;
      Comp_Size    : Interfaces.Unsigned_64;
      Unc_Size     : Interfaces.Unsigned_64;
      Expected_CRC : Interfaces.Unsigned_32;
      Entry_Name   : String;
      Flags        : Interfaces.Unsigned_16;
      Password     : String;
      Target_Path  : String;
      Extract_Image : not null access function
        (Archive_Image : Byte_Array;
         Entry_Name    : String;
         Password      : String;
         Status        : out Status_Code) return Byte_Array;
      Status       : out Status_Code)
   is
      Header     : Byte_Array (0 .. 29);
      Header_Ok  : Boolean;
      Data_Start : Interfaces.Unsigned_64;
   begin
      Status := Ok;

      if Local_Offset + 30 > File_Size
        or else Comp_Size > Interfaces.Unsigned_64 (Natural'Last)
        or else Unc_Size > Interfaces.Unsigned_64 (Interfaces.Unsigned_32'Last)
      then
         Status := Unexpected_End_Of_Input;
         return;
      end if;

      Read_At (File, Local_Offset, Header, Header_Ok);
      if not Header_Ok or else U32_At (Header, 0) /= Local_Signature then
         Status := Unexpected_End_Of_Input;
         return;
      end if;

      Data_Start := Local_Offset + 30
        + Interfaces.Unsigned_64 (U16_At (Header, 26))
        + Interfaces.Unsigned_64 (U16_At (Header, 28));

      if Data_Start + Comp_Size > File_Size then
         Status := Unexpected_End_Of_Input;
         return;
      end if;

      declare
         Payload : Byte_Array (1 .. Natural (Comp_Size));
         Read_Ok : Boolean;
      begin
         Read_At (File, Data_Start, Payload, Read_Ok);
         if not Read_Ok then
            Status := Unexpected_End_Of_Input;
            return;
         end if;

         declare
            Image : constant Byte_Array :=
              Single_Entry_Image
                (Entry_Name => Entry_Name,
                 Flags      => Flags,
                 Method     => Method,
                 CRC        => Expected_CRC,
                 Payload    => Payload,
                 Plain_Size => Interfaces.Unsigned_32 (Unc_Size));
            Decoded : constant Byte_Array :=
              Extract_Image (Image, Entry_Name, Password, Status);
         begin
            if Status /= Ok then
               return;
            end if;

            declare
               Output : SIO.File_Type;
               Raw    : Ada.Streams.Stream_Element_Array
                 (1 .. Ada.Streams.Stream_Element_Offset (Decoded'Length));
               Target : Ada.Streams.Stream_Element_Offset := Raw'First;
            begin
               for B of Decoded loop
                  Raw (Target) := Ada.Streams.Stream_Element (B);
                  Target := Target + 1;
               end loop;
               SIO.Create (Output, SIO.Out_File, Target_Path);
               if Raw'Length > 0 then
                  SIO.Write (Output, Raw);
               end if;
               SIO.Close (Output);
            end;
         end;
      end;
   exception
      when Storage_Error =>
         Status := Insufficient_Memory;
      when others =>
         Status := Unsupported_Method;
   end Extract_Foreign_Member;

   ---------------------------------------------------------------------------
   --  Whole-archive extraction.
   ---------------------------------------------------------------------------

   procedure Extract_To_Directory
     (Archive_Path    : String;
      Destination_Dir : String;
      Safe_Entry_Name : not null access function
        (Entry_Name : String) return Boolean;
      Password        : String;
      Extract_Image   : not null access function
        (Archive_Image : Byte_Array;
         Entry_Name    : String;
         Password      : String;
         Status        : out Status_Code) return Byte_Array;
      Handled         : out Boolean;
      Status          : out Status_Code)
   is
      File      : SIO.File_Type;
      Opened    : Boolean := False;
      File_Size : Interfaces.Unsigned_64;
      CD_Offset : Interfaces.Unsigned_64;
      CD_Size   : Interfaces.Unsigned_64;
      CD_Count  : Natural;
      Found     : Boolean;
   begin
      Handled := False;
      Status := Unsupported_Method;

      if not Ada.Directories.Exists (Archive_Path) then
         Handled := True;
         Status := Input_File_Error;
         return;
      end if;

      SIO.Open (File, SIO.In_File, Archive_Path);
      Opened := True;
      File_Size := Interfaces.Unsigned_64 (SIO.Size (File));

      Find_Central_Directory
        (File, File_Size, CD_Offset, CD_Size, CD_Count, Found);
      if not Found then
         SIO.Close (File);
         return;                      --  not a ZIP this reader recognizes
      end if;

      --  The central directory is proportional to the number of members, not
      --  to the archive size or to any member's size, so it is read whole.
      declare
         Central : Byte_Array (0 .. Natural (CD_Size) - 1);
         Read_Ok : Boolean;
         Pos     : Natural := 0;
      begin
         Read_At (File, CD_Offset, Central, Read_Ok);
         if not Read_Ok then
            SIO.Close (File);
            return;
         end if;

         Handled := True;
         Status := Ok;
         Pos := 0;

         for I in 1 .. CD_Count loop
            exit when Pos + 45 > Central'Last;
            exit when U32_At (Central, Pos) /= Central_Signature;
            declare
               Flags     : constant Interfaces.Unsigned_16 := U16_At (Central, Pos + 8);
               Method    : constant Interfaces.Unsigned_16 := U16_At (Central, Pos + 10);
               CRC       : constant Interfaces.Unsigned_32 := U32_At (Central, Pos + 16);
               Comp_32   : constant Interfaces.Unsigned_32 := U32_At (Central, Pos + 20);
               Unc_32    : constant Interfaces.Unsigned_32 := U32_At (Central, Pos + 24);
               Name_Len  : constant Natural := Natural (U16_At (Central, Pos + 28));
               Extra_Len : constant Natural := Natural (U16_At (Central, Pos + 30));
               Cmt_Len   : constant Natural := Natural (U16_At (Central, Pos + 32));
               Off_32    : constant Interfaces.Unsigned_32 := U32_At (Central, Pos + 42);
               Name_First : constant Natural := Pos + 46;
               Comp, Unc, Local_Offset : Interfaces.Unsigned_64;
               Name       : US.Unbounded_String;
            begin
               exit when Name_First + Name_Len + Extra_Len + Cmt_Len - 1 > Central'Last;

               for I in Name_First .. Name_First + Name_Len - 1 loop
                  US.Append (Name, Character'Val (Natural (Central (I))));
               end loop;

               Resolve_Sizes
                 (Central, Name_First + Name_Len, Extra_Len,
                  Comp_32, Unc_32, Off_32, Comp, Unc, Local_Offset);

               declare
                  Full : constant String := US.To_String (Name);
                  Rel  : constant String :=
                    (if Full'Length > 0 and then Full (Full'Last) = '/'
                     then Full (Full'First .. Full'Last - 1) else Full);
                  Is_Directory : constant Boolean :=
                    Full'Length > 0 and then Full (Full'Last) = '/';
               begin
                  if Rel'Length = 0 or else not Safe_Entry_Name (Rel) then
                     Status := Unsupported_Method;
                     exit;
                  end if;

                  declare
                     Target : constant String := Destination_Dir & "/" & Rel;
                  begin
                     if Is_Directory then
                        Ada.Directories.Create_Path (Target);
                     else
                        Ada.Directories.Create_Path
                          (Ada.Directories.Containing_Directory (Target));
                        if (Flags and 1) = 0
                          and then (Method = Method_Stored
                                    or else Method = Method_Deflate)
                        then
                           Extract_Member
                             (File         => File,
                              File_Size    => File_Size,
                              Local_Offset => Local_Offset,
                              Method       => Method,
                              Comp_Size    => Comp,
                              Unc_Size     => Unc,
                              Expected_CRC => CRC,
                              Target_Path  => Target,
                              Status       => Status);
                        else
                           Extract_Foreign_Member
                             (File         => File,
                              File_Size    => File_Size,
                              Local_Offset => Local_Offset,
                              Method       => Method,
                              Comp_Size    => Comp,
                              Unc_Size     => Unc,
                              Expected_CRC => CRC,
                              Entry_Name   => Full,
                              Flags        => Flags,
                              Password     => Password,
                              Target_Path  => Target,
                              Extract_Image => Extract_Image,
                              Status       => Status);
                        end if;
                        exit when Status /= Ok;
                     end if;
                  end;
               end;

               Pos := Name_First + Name_Len + Extra_Len + Cmt_Len;
            end;
         end loop;
      end;

      SIO.Close (File);
      Opened := False;

   exception
      when Storage_Error =>
         if Opened then
            SIO.Close (File);
         end if;
         Handled := True;
         Status := Insufficient_Memory;

      when others =>
         if Opened then
            SIO.Close (File);
         end if;
         Handled := True;
         Status := Unsupported_Method;
   end Extract_To_Directory;

   procedure Extract_Entry_To_File
     (Archive_Path : String;
      Entry_Name   : String;
      Output_Path  : String;
      Password     : String;
      Extract_Image : not null access function
        (Archive_Image : Byte_Array;
         Entry_Name    : String;
         Password      : String;
         Status        : out Status_Code) return Byte_Array;
      Handled      : out Boolean;
      Status       : out Status_Code)
   is
      File      : SIO.File_Type;
      File_Size : Interfaces.Unsigned_64;
      CD_Offset : Interfaces.Unsigned_64;
      CD_Size   : Interfaces.Unsigned_64;
      CD_Count  : Natural;
      Found     : Boolean;
   begin
      Handled := False;
      Status := Unsupported_Method;

      if Entry_Name'Length = 0 then
         Handled := True;
         Status := Unsupported_Method;
         return;
      end if;

      if not Ada.Directories.Exists (Archive_Path) then
         Handled := True;
         Status := Input_File_Error;
         return;
      end if;

      SIO.Open (File, SIO.In_File, Archive_Path);
      File_Size := Interfaces.Unsigned_64 (SIO.Size (File));
      Find_Central_Directory
        (File, File_Size, CD_Offset, CD_Size, CD_Count, Found);
      if not Found then
         SIO.Close (File);
         return;
      end if;

      declare
         Central : Byte_Array (0 .. Natural (CD_Size) - 1);
         Read_Ok : Boolean;
         Pos     : Natural := 0;
         Matched : Boolean := False;
      begin
         Read_At (File, CD_Offset, Central, Read_Ok);
         if not Read_Ok then
            SIO.Close (File);
            return;
         end if;

         for I in 1 .. CD_Count loop
            exit when Pos + 45 > Central'Last;
            exit when U32_At (Central, Pos) /= Central_Signature;
            declare
               Flags     : constant Interfaces.Unsigned_16 := U16_At (Central, Pos + 8);
               Method    : constant Interfaces.Unsigned_16 := U16_At (Central, Pos + 10);
               CRC       : constant Interfaces.Unsigned_32 := U32_At (Central, Pos + 16);
               Comp_32   : constant Interfaces.Unsigned_32 := U32_At (Central, Pos + 20);
               Unc_32    : constant Interfaces.Unsigned_32 := U32_At (Central, Pos + 24);
               Name_Len  : constant Natural := Natural (U16_At (Central, Pos + 28));
               Extra_Len : constant Natural := Natural (U16_At (Central, Pos + 30));
               Cmt_Len   : constant Natural := Natural (U16_At (Central, Pos + 32));
               Off_32    : constant Interfaces.Unsigned_32 := U32_At (Central, Pos + 42);
               Name_First : constant Natural := Pos + 46;
               Comp, Unc, Local_Offset : Interfaces.Unsigned_64;
               Name       : US.Unbounded_String;
            begin
               exit when Name_First + Name_Len + Extra_Len + Cmt_Len - 1 > Central'Last;

               for K in Name_First .. Name_First + Name_Len - 1 loop
                  US.Append (Name, Character'Val (Natural (Central (K))));
               end loop;

               if US.To_String (Name) = Entry_Name then
                  Matched := True;

                  Resolve_Sizes
                    (Central, Name_First + Name_Len, Extra_Len,
                     Comp_32, Unc_32, Off_32, Comp, Unc, Local_Offset);

                  Handled := True;
                  if (Flags and 1) = 0
                    and then (Method = Method_Stored
                              or else Method = Method_Deflate)
                  then
                     Extract_Member
                       (File         => File,
                        File_Size    => File_Size,
                        Local_Offset => Local_Offset,
                        Method       => Method,
                        Comp_Size    => Comp,
                        Unc_Size     => Unc,
                        Expected_CRC => CRC,
                        Target_Path  => Output_Path,
                        Status       => Status);
                  else
                     Extract_Foreign_Member
                       (File         => File,
                        File_Size    => File_Size,
                        Local_Offset => Local_Offset,
                        Method       => Method,
                        Comp_Size    => Comp,
                        Unc_Size     => Unc,
                        Expected_CRC => CRC,
                        Entry_Name   => Entry_Name,
                        Flags        => Flags,
                        Password     => Password,
                        Target_Path  => Output_Path,
                        Extract_Image => Extract_Image,
                        Status       => Status);
                  end if;
                  exit;
               end if;

               Pos := Name_First + Name_Len + Extra_Len + Cmt_Len;
            end;
         end loop;

         SIO.Close (File);

         --  A ZIP this reader understood, whose directory simply has no such
         --  member, is a definite answer rather than a reason to re-read the
         --  archive whole.
         if not Matched then
            Handled := True;
            Status := Unsupported_Method;
         end if;
      end;

   exception
      when Storage_Error =>
         Handled := True;
         Status := Insufficient_Memory;
      when others =>
         Handled := True;
         Status := Unsupported_Method;
   end Extract_Entry_To_File;

   function List_Entries
     (Archive_Path : String;
      Handled      : out Boolean;
      Status       : out Status_Code) return Archive_Entry_Array
   is
      None      : constant Archive_Entry_Array (1 .. 0) :=
        [others => (others => <>)];
      File      : SIO.File_Type;
      File_Size : Interfaces.Unsigned_64;
      CD_Offset : Interfaces.Unsigned_64;
      CD_Size   : Interfaces.Unsigned_64;
      CD_Count  : Natural;
      Found     : Boolean;
   begin
      Handled := False;
      Status := Unsupported_Method;

      if not Ada.Directories.Exists (Archive_Path) then
         Handled := True;
         Status := Input_File_Error;
         return None;
      end if;

      SIO.Open (File, SIO.In_File, Archive_Path);
      File_Size := Interfaces.Unsigned_64 (SIO.Size (File));
      Find_Central_Directory
        (File, File_Size, CD_Offset, CD_Size, CD_Count, Found);
      if not Found then
         SIO.Close (File);
         return None;
      end if;

      declare
         Central : Byte_Array (0 .. Natural (CD_Size) - 1);
         Read_Ok : Boolean;
         Pos     : Natural := 0;
         Found_N : Natural := 0;
         Result  : Archive_Entry_Array (1 .. CD_Count) :=
           [others => (others => <>)];
      begin
         Read_At (File, CD_Offset, Central, Read_Ok);
         SIO.Close (File);
         if not Read_Ok then
            return None;
         end if;

         for I in 1 .. CD_Count loop
            exit when Pos + 45 > Central'Last;
            exit when U32_At (Central, Pos) /= Central_Signature;
            declare
               Method    : constant Interfaces.Unsigned_16 := U16_At (Central, Pos + 10);
               CRC       : constant Interfaces.Unsigned_32 := U32_At (Central, Pos + 16);
               Comp_32   : constant Interfaces.Unsigned_32 := U32_At (Central, Pos + 20);
               Unc_32    : constant Interfaces.Unsigned_32 := U32_At (Central, Pos + 24);
               Name_Len  : constant Natural := Natural (U16_At (Central, Pos + 28));
               Extra_Len : constant Natural := Natural (U16_At (Central, Pos + 30));
               Cmt_Len   : constant Natural := Natural (U16_At (Central, Pos + 32));
               Off_32    : constant Interfaces.Unsigned_32 := U32_At (Central, Pos + 42);
               Name_First : constant Natural := Pos + 46;
               Comp, Unc, Local_Offset : Interfaces.Unsigned_64;
               Name       : US.Unbounded_String;
            begin
               exit when Name_First + Name_Len + Extra_Len + Cmt_Len - 1 > Central'Last;

               for K in Name_First .. Name_First + Name_Len - 1 loop
                  US.Append (Name, Character'Val (Natural (Central (K))));
               end loop;

               Resolve_Sizes
                 (Central, Name_First + Name_Len, Extra_Len,
                  Comp_32, Unc_32, Off_32, Comp, Unc, Local_Offset);

               Found_N := Found_N + 1;
               Result (Found_N) :=
                 (Name              => Name,
                  Is_Directory      =>
                    Name_Len > 0
                    and then Central (Name_First + Name_Len - 1) =
                      Byte (Character'Pos ('/')),
                  Compression       => Method,
                  Uncompressed_Size => Unc,
                  Compressed_Size   => Comp,
                  CRC_32            => CRC);

               Pos := Name_First + Name_Len + Extra_Len + Cmt_Len;
            end;
         end loop;

         Handled := True;
         Status := Ok;
         return Result (1 .. Found_N);
      end;

   exception
      when Storage_Error =>
         Handled := True;
         Status := Insufficient_Memory;
         return None;
      when others =>
         Handled := True;
         Status := Unsupported_Method;
         return None;
   end List_Entries;

end Zlib.ZIP_Streaming_Extraction;
