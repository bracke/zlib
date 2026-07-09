with Ada.Streams; use Ada.Streams;

package body Zlib.Fuzzing is
   use type Interfaces.Unsigned_32;

   function Next
     (Seed : in out Interfaces.Unsigned_32)
      return Interfaces.Unsigned_32 is
   begin
      Seed := Seed * 1_664_525 + 1_013_904_223;
      return Seed;
   end Next;

   function Pick
     (Seed  : in out Interfaces.Unsigned_32;
      Limit : Positive)
      return Natural is
   begin
      return Natural (Next (Seed) mod Interfaces.Unsigned_32 (Limit));
   end Pick;

   function Random_Bytes
     (Seed   : in out Interfaces.Unsigned_32;
      Length : Natural)
      return Byte_Array is
   begin
      if Length = 0 then
         return Empty : Byte_Array (1 .. 0) do
            null;
         end return;
      end if;

      return Result : Byte_Array (0 .. Length - 1) do
         for I in Result'Range loop
            Result (I) := Byte (Next (Seed) mod 256);
         end loop;
      end return;
   end Random_Bytes;

   function To_Stream
     (Input : Byte_Array)
      return Ada.Streams.Stream_Element_Array is
   begin
      if Input'Length = 0 then
         return Empty : Ada.Streams.Stream_Element_Array (1 .. 0) do
            null;
         end return;
      end if;

      return Result : Ada.Streams.Stream_Element_Array
        (Ada.Streams.Stream_Element_Offset (Input'First) ..
         Ada.Streams.Stream_Element_Offset (Input'Last)) do
         for I in Input'Range loop
            Result (Ada.Streams.Stream_Element_Offset (I)) :=
              Ada.Streams.Stream_Element (Input (I));
         end loop;
      end return;
   end To_Stream;

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

   function Mix
     (Value : Interfaces.Unsigned_32;
      Byte_Value : Byte)
      return Interfaces.Unsigned_32 is
   begin
      return Value * 16_777_619 xor Interfaces.Unsigned_32 (Byte_Value);
   end Mix;

   function Mutated
     (Input : Byte_Array;
      Seed  : in out Interfaces.Unsigned_32;
      Step  : Natural)
      return Byte_Array is
   begin
      if Input'Length = 0 then
         return Random_Bytes (Seed, 1);
      end if;

      case Step mod 8 is
         when 0 =>
            declare
               Result : Byte_Array := Input;
               Pos    : constant Natural := Input'First + Pick (Seed, Input'Length);
               Bit    : constant Byte := Byte (2 ** Pick (Seed, 8));
            begin
               Result (Pos) := Result (Pos) xor Bit;
               return Result;
            end;
         when 1 =>
            declare
               New_Len : constant Natural := Pick (Seed, Input'Length + 1);
            begin
               if New_Len = 0 then
                  return Empty : Byte_Array (1 .. 0) do
                     null;
                  end return;
               end if;

               declare
                  Result : Byte_Array (0 .. New_Len - 1);
               begin
                  for I in Result'Range loop
                     Result (I) := Input (Input'First + I);
                  end loop;
                  return Result;
               end;
            end;
         when 2 =>
            declare
               Pos    : constant Natural := Input'First + Pick (Seed, Input'Length);
               Result : Byte_Array (0 .. Input'Length);
               Out_I  : Natural := 0;
            begin
               for I in Input'Range loop
                  Result (Out_I) := Input (I);
                  Out_I := Out_I + 1;
                  if I = Pos then
                     Result (Out_I) := Input (I);
                     Out_I := Out_I + 1;
                  end if;
               end loop;
               return Result;
            end;
         when 3 =>
            if Input'Length = 1 then
               return Input;
            end if;
            declare
               Pos    : constant Natural := Input'First + Pick (Seed, Input'Length);
               Result : Byte_Array (0 .. Input'Length - 2);
               Out_I  : Natural := 0;
            begin
               for I in Input'Range loop
                  if I /= Pos then
                     Result (Out_I) := Input (I);
                     Out_I := Out_I + 1;
                  end if;
               end loop;
               return Result;
            end;
         when 4 =>
            declare
               Result : Byte_Array := Input;
            begin
               Result (Result'Last) := Result (Result'Last) xor 16#FF#;
               return Result;
            end;
         when 5 =>
            declare
               Result : Byte_Array := Input;
            begin
               Result (Result'First) := Result (Result'First) xor 16#20#;
               return Result;
            end;
         when 6 =>
            declare
               Result : Byte_Array := Input;
            begin
               for N in 0 .. Natural'Min (3, Input'Length - 1) loop
                  Result (Result'Last - N) :=
                    Result (Result'Last - N) xor Byte (16#A5# + N);
               end loop;
               return Result;
            end;
         when others =>
            declare
               Result : Byte_Array := Input;
               Stop   : constant Natural :=
                 Natural'Min (Result'Last, Result'First + 3);
            begin
               for I in Result'First .. Stop loop
                  Result (I) := Result (I) xor 16#5A#;
               end loop;
               return Result;
            end;
      end case;
   end Mutated;

   function Hex_Char (Value : Natural) return Character
     with Pre => Value <= 15,
          SPARK_Mode => On
   is
      Hex : constant String := "0123456789ABCDEF";
   begin
      return Hex (Value + 1);
   end Hex_Char;

   function Hex_Snippet
     (Input : Byte_Array;
      Limit : Natural := 16)
      return String is
      Count : constant Natural := Natural'Min (Input'Length, Limit);
   begin
      if Count = 0 then
         return "";
      end if;

      declare
         Result : String (1 .. Count * 2);
         J      : Natural := 1;
      begin
         for I in 0 .. Count - 1 loop
            declare
               V : constant Natural := Natural (Input (Input'First + I));
            begin
               Result (J) := Hex_Char (V / 16);
               Result (J + 1) := Hex_Char (V mod 16);
               J := J + 2;
            end;
         end loop;
         return Result;
      end;
   end Hex_Snippet;

   procedure Note_Input
     (Result : in out Fuzz_Result;
      Input  : Byte_Array) is
      Hex : constant String := Hex_Snippet (Input, 16);
   begin
      Result.Last_Input_Length := Input'Length;
      Result.Last_Hex_Length := Hex'Length;
      Result.Last_Hex := [others => ' '];
      if Hex'Length > 0 then
         Result.Last_Hex (1 .. Hex'Length) := Hex;
      end if;
   end Note_Input;

   procedure Account
     (Result : in out Fuzz_Result;
      Status : Status_Code) is
   begin
      Result.Runs := Result.Runs + 1;
      Result.Digest := Result.Digest * 33 + Interfaces.Unsigned_32 (Status_Code'Pos (Status));
      if Status = Ok then
         Result.Success := Result.Success + 1;
      else
         Result.Failures := Result.Failures + 1;
      end if;
   end Account;

   procedure Account_Exception (Result : in out Fuzz_Result) is
   begin
      Result.Runs := Result.Runs + 1;
      Result.Crashes := Result.Crashes + 1;
      Result.Digest := Result.Digest * 33 + 16#BAD#;
   end Account_Exception;

   procedure Fuzz_Inflate_Once
     (Result : in out Fuzz_Result;
      Seed   : in out Interfaces.Unsigned_32;
      Header : Header_Type) is
      Status : Status_Code;
      Len    : constant Natural := Pick (Seed, 96);
      Input  : constant Byte_Array := Random_Bytes (Seed, Len);
   begin
      Note_Input (Result, Input);
      declare
         Output : constant Byte_Array := Inflate_With_Header (Input, Header, Status);
      begin
         Result.Digest := Result.Digest + Interfaces.Unsigned_32 (Output'Length);
         Account (Result, Status);
      end;
   exception
      when others =>
         Account_Exception (Result);
   end Fuzz_Inflate_Once;

   procedure Fuzz_Streaming_Inflate_Once
     (Result : in out Fuzz_Result;
      Seed   : in out Interfaces.Unsigned_32;
      Header : Header_Type) is
      Filter   : Filter_Type;
      Status   : Status_Code := Ok;
      Input    : constant Byte_Array := Random_Bytes (Seed, Pick (Seed, 80));
      Stream   : constant Ada.Streams.Stream_Element_Array := To_Stream (Input);
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Output   : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Pick (Seed, 8) + 1));
      First    : Ada.Streams.Stream_Element_Offset := Stream'First;
      Loops    : Natural := 0;
   begin
      Note_Input (Result, Input);
      Inflate_Init (Filter, Header);
      while First <= Stream'Last and then Loops < 128 loop
         declare
            Last : constant Ada.Streams.Stream_Element_Offset :=
              Ada.Streams.Stream_Element_Offset'Min
                (Stream'Last,
                 First + Ada.Streams.Stream_Element_Offset (Pick (Seed, 5)));
         begin
            Translate
              (Filter, Stream (First .. Last), In_Last, Output, Out_Last,
               (if Pick (Seed, 4) = 0 then Finish else No_Flush));
            if In_Last >= First then
               First := In_Last + 1;
            else
               First := Last + 1;
            end if;
         end;
         Loops := Loops + 1;
      end loop;
      if Loops >= 128 or else not Stream_End (Filter) then
         Status := Unexpected_End_Of_Input;
      end if;
      Close (Filter, Ignore_Error => True);
      Account (Result, Status);
   exception
      when Zlib_Error | Status_Error =>
         Close (Filter, Ignore_Error => True);
         Account (Result, Invalid_Block_Type);
      when others =>
         Close (Filter, Ignore_Error => True);
         Account_Exception (Result);
   end Fuzz_Streaming_Inflate_Once;

   function Patterned_Bytes
     (Seed       : in out Interfaces.Unsigned_32;
      Max_Length : Positive)
      return Byte_Array is
      Length  : constant Natural := Pick (Seed, Max_Length);
      Pattern : constant Natural := Pick (Seed, 5);
   begin
      if Pattern = 0 then
         return Random_Bytes (Seed, Length);
      end if;

      if Length = 0 then
         return Empty : Byte_Array (1 .. 0) do
            null;
         end return;
      end if;

      return Result : Byte_Array (0 .. Length - 1) do
         case Pattern is
            when 1 =>
               declare
                  B : constant Byte := Byte (Pick (Seed, 256));
               begin
                  for I in Result'Range loop
                     Result (I) := B;
                  end loop;
               end;
            when 2 =>
               for I in Result'Range loop
                  Result (I) := Byte (I mod 256);
               end loop;
            when 3 =>
               for I in Result'Range loop
                  Result (I) :=
                    Byte (Character'Pos ('a') + Pick (Seed, 26));
               end loop;
            when others =>
               declare
                  Alphabet : constant Natural := Pick (Seed, 4) + 2;
               begin
                  for I in Result'Range loop
                     Result (I) :=
                       Byte (Character'Pos ('A') + Natural (I mod Alphabet));
                  end loop;
               end;
         end case;
      end return;
   end Patterned_Bytes;

   function Compress_For_Header
     (Payload : Byte_Array;
      Header  : Header_Type;
      Mode    : Compression_Mode;
      Status  : out Status_Code)
      return Byte_Array is
   begin
      case Header is
         when GZip =>
            return GZip (Payload, Mode, Status);
         when Raw_Deflate =>
            return Deflate_Raw (Payload, Mode, Status);
         when others =>
            return Deflate (Payload, Mode, Status);
      end case;
   end Compress_For_Header;

   function Compress_For_Header
     (Payload : Byte_Array;
      Header  : Header_Type;
      Level   : Compression_Level;
      Status  : out Status_Code)
      return Byte_Array is
   begin
      case Header is
         when GZip =>
            return GZip (Payload, Level, Status);
         when Raw_Deflate =>
            return Deflate_Raw (Payload, Level, Status);
         when others =>
            return Deflate (Payload, Level, Status);
      end case;
   end Compress_For_Header;

   procedure Roundtrip
     (Result : in out Fuzz_Result;
      Seed   : in out Interfaces.Unsigned_32;
      Header : Header_Type;
      Mode   : Compression_Mode) is
      Payload : constant Byte_Array := Patterned_Bytes (Seed, 128);
      CStat   : Status_Code;
      IStat   : Status_Code;
   begin
      Note_Input (Result, Payload);
      declare
         Compressed : constant Byte_Array :=
           Compress_For_Header (Payload, Header, Mode, CStat);
      begin
         if CStat /= Ok then
            Account (Result, CStat);
            return;
         end if;

         declare
            Inflated : constant Byte_Array := Inflate_With_Header (Compressed, Header, IStat);
         begin
            if IStat = Ok and then Inflated = Payload then
               Account (Result, Ok);
            elsif IStat = Ok then
               Account (Result, Invalid_Checksum);
            else
               Account (Result, IStat);
            end if;
         end;
      end;
   exception
      when others =>
         Account_Exception (Result);
   end Roundtrip;

   procedure Level_Roundtrip_Once
     (Result : in out Fuzz_Result;
      Seed   : in out Interfaces.Unsigned_32) is
      Payload : constant Byte_Array := Patterned_Bytes (Seed, 128);
      Header  : constant Header_Type :=
        (case Pick (Seed, 3) is
           when 0      => Zlib_Header,
           when 1      => GZip,
           when others => Raw_Deflate);
      Level   : constant Compression_Level := Compression_Level (Pick (Seed, 10));
      CStat   : Status_Code;
      IStat   : Status_Code;
   begin
      Note_Input (Result, Payload);
      declare
         Compressed : constant Byte_Array :=
           Compress_For_Header (Payload, Header, Level, CStat);
      begin
         Result.Digest :=
           Result.Digest + Interfaces.Unsigned_32 (Compression_Level'Pos (Level));
         if CStat /= Ok then
            Account (Result, CStat);
            return;
         end if;

         declare
            Inflated : constant Byte_Array := Inflate_With_Header (Compressed, Header, IStat);
         begin
            if IStat = Ok and then Inflated = Payload then
               Account (Result, Ok);
            elsif IStat = Ok then
               Account (Result, Invalid_Checksum);
            else
               Account (Result, IStat);
            end if;
         end;
      end;
   exception
      when others =>
         Account_Exception (Result);
   end Level_Roundtrip_Once;

   procedure Wrapper_Mix_Once
     (Result : in out Fuzz_Result;
      Seed   : in out Interfaces.Unsigned_32) is
      Payload : constant Byte_Array := Patterned_Bytes (Seed, 96);
      Header  : constant Header_Type :=
        (case Pick (Seed, 3) is
           when 0      => Zlib_Header,
           when 1      => GZip,
           when others => Raw_Deflate);
      Mode    : constant Compression_Mode :=
        Compression_Mode'Val (Pick (Seed, Compression_Mode'Pos (Compression_Mode'Last) + 1));
      CStat   : Status_Code;
      IStat   : Status_Code;
   begin
      Note_Input (Result, Payload);
      declare
         Compressed : constant Byte_Array :=
           Compress_For_Header (Payload, Header, Mode, CStat);
      begin
         if CStat /= Ok then
            Account (Result, CStat);
            return;
         end if;

         if Header = GZip and then Pick (Seed, 4) = 0 then
            declare
               Tail_Payload : constant Byte_Array :=
                 Random_Bytes (Seed, Pick (Seed, 48));
               Tail         : constant Byte_Array := GZip (Tail_Payload, Mode, CStat);
               Joined       : constant Byte_Array := Compressed & Tail;
               Inflated     : constant Byte_Array :=
                 Inflate_With_Header (Joined, GZip, Multi_Member, IStat);
            begin
               if CStat = Ok and then IStat = Ok and then Inflated = (Payload & Tail_Payload) then
                  Account (Result, Ok);
               elsif CStat = Ok and then IStat = Ok then
                  Account (Result, Invalid_Checksum);
               elsif CStat /= Ok then
                  Account (Result, CStat);
               else
                  Account (Result, IStat);
               end if;
            end;
         else
            declare
               Decode_Header : constant Header_Type :=
                 (if Pick (Seed, 5) = 0 then
                    Header_Type'Val (Pick (Seed, Header_Type'Pos (Header_Type'Last) + 1))
                  else
                    Header);
               Inflated : constant Byte_Array :=
                 Inflate_With_Header (Compressed, Decode_Header, IStat);
            begin
               Result.Digest :=
                 Result.Digest + Interfaces.Unsigned_32 (Header_Type'Pos (Decode_Header));
               if Decode_Header = Header and then IStat = Ok and then Inflated = Payload then
                  Account (Result, Ok);
               elsif Decode_Header = Header and then IStat = Ok then
                  Account (Result, Invalid_Checksum);
               elsif Decode_Header /= Header and then IStat /= Ok then
                  Account (Result, Ok);
               elsif Decode_Header /= Header then
                  Account (Result, Invalid_Header);
               else
                  Account (Result, IStat);
               end if;
            end;
         end if;
      end;
   exception
      when others =>
         Account_Exception (Result);
   end Wrapper_Mix_Once;

   function Random_Text
     (Seed   : in out Interfaces.Unsigned_32;
      Length : Natural)
      return String is
   begin
      if Length = 0 then
         return "";
      end if;

      return Result : String (1 .. Length) do
         for I in Result'Range loop
            Result (I) := Character'Val (Character'Pos ('A') + Pick (Seed, 26));
         end loop;
      end return;
   end Random_Text;

   procedure GZip_Metadata_Once
     (Result : in out Fuzz_Result;
      Seed   : in out Interfaces.Unsigned_32) is
      Payload  : constant Byte_Array := Random_Bytes (Seed, Pick (Seed, 96));
      Metadata : GZip_Metadata := No_GZip_Metadata;
      Mode     : constant Compression_Mode :=
        Compression_Mode'Val (Pick (Seed, Compression_Mode'Pos (Compression_Mode'Last) + 1));
      CStat    : Status_Code;
      IStat    : Status_Code;
   begin
      Note_Input (Result, Payload);
      if Pick (Seed, 2) = 0 then
         Set_Name (Metadata, Random_Text (Seed, Pick (Seed, 12) + 1));
      end if;

      if Pick (Seed, 2) = 0 then
         Set_Comment (Metadata, Random_Text (Seed, Pick (Seed, 20) + 1));
      end if;

      if Pick (Seed, 2) = 0 then
         Set_Extra (Metadata, Random_Bytes (Seed, Pick (Seed, 32)));
      end if;

      if Pick (Seed, 2) = 0 then
         Set_Header_CRC (Metadata, True);
      end if;

      Set_MTime (Metadata, Next (Seed));
      Set_XFL (Metadata, Byte (Pick (Seed, 256)));
      Set_OS (Metadata, Byte (Pick (Seed, 256)));

      declare
         Compressed : constant Byte_Array := GZip (Payload, Mode, Metadata, CStat);
      begin
         if CStat /= Ok then
            Account (Result, CStat);
            return;
         end if;

         declare
            Inflated : constant Byte_Array := Inflate_With_Header (Compressed, GZip, IStat);
         begin
            if IStat = Ok and then Inflated = Payload then
               Account (Result, Ok);
            elsif IStat = Ok then
               Account (Result, Invalid_Checksum);
            else
               Account (Result, IStat);
            end if;
         end;
      end;
   exception
      when others =>
         Account_Exception (Result);
   end GZip_Metadata_Once;

   procedure Dictionary_Once
     (Result : in out Fuzz_Result;
      Seed   : in out Interfaces.Unsigned_32) is
      Payload : constant Byte_Array := Random_Bytes (Seed, Pick (Seed, 96));
      Dict    : constant Byte_Array := Random_Bytes (Seed, Pick (Seed, 32) + 1);
      CStat   : Status_Code;
      IStat   : Status_Code;
   begin
      Note_Input (Result, Payload);
      declare
         Compressed : constant Byte_Array := Deflate_With_Dictionary (Payload, Dict, Auto, CStat);
      begin
         if CStat /= Ok then
            Account (Result, CStat);
            return;
         end if;

         declare
            Use_Wrong : constant Boolean := Pick (Seed, 4) = 0;
            Try_Dict  : constant Byte_Array :=
              (if Use_Wrong then Mutated (Dict, Seed, Pick (Seed, 64)) else Dict);
            Inflated  : constant Byte_Array :=
              Inflate_With_Dictionary (Compressed, Try_Dict, IStat);
         begin
            if Use_Wrong and then IStat /= Ok then
               Account (Result, Ok);
            elsif IStat = Ok and then Inflated = Payload then
               Account (Result, Ok);
            elsif IStat = Ok then
               Account (Result, Invalid_Checksum);
            else
               Account (Result, IStat);
            end if;
         end;
      end;
   exception
      when others =>
         Account_Exception (Result);
   end Dictionary_Once;

   procedure Mutation_Once
     (Result : in out Fuzz_Result;
      Seed   : in out Interfaces.Unsigned_32) is
      Payload : constant Byte_Array := Random_Bytes (Seed, Pick (Seed, 96));
      Header  : constant Header_Type :=
        (case Pick (Seed, 3) is
           when 0      => Zlib_Header,
           when 1      => GZip,
           when others => Raw_Deflate);
      Mode    : constant Compression_Mode :=
        Compression_Mode'Val (Pick (Seed, Compression_Mode'Pos (Compression_Mode'Last) + 1));
      CStat   : Status_Code;
      IStat   : Status_Code;
   begin
      declare
         Valid : constant Byte_Array :=
           Compress_For_Header (Payload, Header, Mode, CStat);
      begin
         if CStat /= Ok then
            Account (Result, CStat);
            return;
         end if;
         declare
            Broken : constant Byte_Array := Mutated (Valid, Seed, Pick (Seed, 64));
            Plain  : constant Byte_Array := Inflate_With_Header (Broken, Header, IStat);
         begin
            Note_Input (Result, Broken);
            Result.Digest := Result.Digest + Interfaces.Unsigned_32 (Plain'Length);
            Account (Result, IStat);
         end;
      end;
   exception
      when others =>
         Account_Exception (Result);
   end Mutation_Once;

   procedure Flush_Roundtrip_Once
     (Result : in out Fuzz_Result;
      Seed   : in out Interfaces.Unsigned_32) is
      Payload      : constant Byte_Array := Patterned_Bytes (Seed, 160);
      Header       : constant Header_Type :=
        (case Pick (Seed, 3) is
           when 0      => Zlib_Header,
           when 1      => GZip,
           when others => Raw_Deflate);
      Mode         : constant Compression_Mode :=
        Compression_Mode'Val
          (Pick
             (Seed, Compression_Mode'Pos (Compression_Mode'Last) + 1));
      Input_Chunk  : constant Positive := Pick (Seed, 9) + 1;
      Output_Chunk : constant Positive := Pick (Seed, 7) + 1;
      Filter       : Compression_Filter_Type;
      Encoded      : Byte_Array (0 .. 4095) := [others => 0];
      Encoded_Len  : Natural := 0;
      Position     : Natural := Payload'First;
      Loops        : Natural := 0;

      procedure Capture
        (Data : Ada.Streams.Stream_Element_Array;
         Last : Ada.Streams.Stream_Element_Offset)
      is
         Count : constant Natural := Produced (Data, Last);
      begin
         if Encoded_Len + Count > Encoded'Length then
            raise Constraint_Error;
         end if;

         for I in 0 .. Count - 1 loop
            Encoded (Encoded'First + Encoded_Len + I) :=
              Byte (Data (Data'First + Ada.Streams.Stream_Element_Offset (I)));
         end loop;
         Encoded_Len := Encoded_Len + Count;
      end Capture;

      procedure Drain
        (Flush : Flush_Mode)
      is
         Output   : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Output_Chunk));
         Out_Last : Ada.Streams.Stream_Element_Offset;
         Count    : Natural;
      begin
         loop
            Compress_Flush (Filter, Output, Out_Last, Flush);
            Count := Produced (Output, Out_Last);
            Capture (Output, Out_Last);
            Loops := Loops + 1;
            exit when Count = 0;
            if Loops >= 1_024 then
               raise Constraint_Error;
            end if;
         end loop;
      end Drain;
   begin
      Note_Input (Result, Payload);
      Deflate_Init (Filter, Header => Header, Mode => Mode);

      while Position <= Payload'Last loop
         declare
            Count      : constant Natural :=
              Natural'Min (Input_Chunk, Payload'Last - Position + 1);
            Input      : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Count));
            Output     : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Chunk));
            In_Last    : Ada.Streams.Stream_Element_Offset;
            Out_Last   : Ada.Streams.Stream_Element_Offset;
            Flush_Pick : constant Natural := Pick (Seed, 5);
            Flush      : constant Flush_Mode :=
              (case Flush_Pick is
                 when 0      => Sync_Flush,
                 when 1      => Full_Flush,
                 when others => No_Flush);
            Used       : Natural;
            Made       : Natural;
         begin
            for I in 0 .. Count - 1 loop
               Input (Ada.Streams.Stream_Element_Offset (I + 1)) :=
                 Ada.Streams.Stream_Element (Payload (Position + I));
            end loop;

            Compress (Filter, Input, In_Last, Output, Out_Last, Flush);
            Capture (Output, Out_Last);
            Used := Consumed (Input, In_Last);
            Made := Produced (Output, Out_Last);

            Result.Digest :=
              Result.Digest + Interfaces.Unsigned_32 (Flush_Mode'Pos (Flush));

            if Flush in Sync_Flush | Full_Flush then
               Drain (No_Flush);
            end if;

            if Used > 0 then
               Position := Position + Used;
            elsif Made = 0 then
               Account (Result, Output_File_Error);
               Compress_Close (Filter, Ignore_Error => True);
               return;
            end if;

            Loops := Loops + 1;
            if Loops >= 1_024 then
               Account (Result, Unexpected_End_Of_Input);
               Compress_Close (Filter, Ignore_Error => True);
               return;
            end if;
         end;
      end loop;

      while not Compress_Stream_End (Filter) loop
         declare
            Output   : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Output_Chunk));
            Out_Last : Ada.Streams.Stream_Element_Offset;
         begin
            Compress_Flush (Filter, Output, Out_Last, Finish);
            Capture (Output, Out_Last);
         end;
         Loops := Loops + 1;
         if Loops >= 1_024 then
            Account (Result, Unexpected_End_Of_Input);
            Compress_Close (Filter, Ignore_Error => True);
            return;
         end if;
      end loop;

      Compress_Close (Filter);

      declare
         Status : Status_Code;
         Plain  : constant Byte_Array :=
           Inflate_With_Header
             (Encoded (Encoded'First .. Encoded'First + Encoded_Len - 1),
              Header,
              Status);
      begin
         Result.Digest :=
           Result.Digest + Interfaces.Unsigned_32 (Header_Type'Pos (Header));
         Result.Digest :=
           Result.Digest + Interfaces.Unsigned_32 (Compression_Mode'Pos (Mode));

         if Status = Ok and then Plain = Payload then
            Account (Result, Ok);
         elsif Status = Ok then
            Account (Result, Invalid_Checksum);
         else
            Account (Result, Status);
         end if;
      end;
   exception
      when others =>
         Compress_Close (Filter, Ignore_Error => True);
         Account_Exception (Result);
   end Flush_Roundtrip_Once;

   procedure Decode_Tiny_Stream
     (Result      : in out Fuzz_Result;
      Input       : Byte_Array;
      Expected    : Byte_Array;
      Header      : Header_Type;
      Member_Mode : GZip_Member_Mode := Single_Member) is
      Filter      : Filter_Type;
      Stream      : constant Ada.Streams.Stream_Element_Array := To_Stream (Input);
      In_Last     : Ada.Streams.Stream_Element_Offset;
      Out_Last    : Ada.Streams.Stream_Element_Offset;
      Output      : Ada.Streams.Stream_Element_Array (1 .. 1);
      Decoded     : Byte_Array (0 .. Expected'Length + 8);
      Decoded_Len : Natural := 0;
      First       : Ada.Streams.Stream_Element_Offset := Stream'First;
      Loops       : Natural := 0;
   begin
      if Header = GZip then
         Inflate_Init (Filter, Header, Member_Mode);
      else
         Inflate_Init (Filter, Header);
      end if;

      while First <= Stream'Last
        and then not Stream_End (Filter)
        and then Loops < 768
      loop
         Translate
           (Filter, Stream (First .. First), In_Last, Output, Out_Last,
            (if First = Stream'Last then Finish else No_Flush));

         if Out_Last >= Output'First
           and then Decoded_Len <= Decoded'Last
         then
            Decoded (Decoded_Len) := Byte (Output (Output'First));
            Decoded_Len := Decoded_Len + 1;
         end if;

         if In_Last >= First then
            First := In_Last + 1;
         else
            Flush (Filter, Output, Out_Last, No_Flush);
            if Out_Last >= Output'First
              and then Decoded_Len <= Decoded'Last
            then
               Decoded (Decoded_Len) := Byte (Output (Output'First));
               Decoded_Len := Decoded_Len + 1;
            end if;
         end if;
         Loops := Loops + 1;
      end loop;

      while not Stream_End (Filter) and then Loops < 768 loop
         Flush (Filter, Output, Out_Last, Finish);
         if Out_Last >= Output'First
           and then Decoded_Len <= Decoded'Last
         then
            Decoded (Decoded_Len) := Byte (Output (Output'First));
            Decoded_Len := Decoded_Len + 1;
         end if;
         Loops := Loops + 1;
      end loop;

      Close (Filter, Ignore_Error => True);
      Result.Digest := Result.Digest + Interfaces.Unsigned_32 (Header_Type'Pos (Header));
      Result.Digest :=
        Result.Digest + Interfaces.Unsigned_32 (GZip_Member_Mode'Pos (Member_Mode));

      if Loops >= 768 then
         Account (Result, Unexpected_End_Of_Input);
      elsif Decoded_Len = Expected'Length then
         if Expected'Length = 0 then
            Account (Result, Ok);
         elsif Decoded (0 .. Decoded_Len - 1) = Expected then
            Account (Result, Ok);
         else
            Account (Result, Invalid_Checksum);
         end if;
      else
         Account (Result, Invalid_Checksum);
      end if;
   exception
      when Zlib_Error | Status_Error =>
         Close (Filter, Ignore_Error => True);
         Account (Result, Invalid_Block_Type);
      when others =>
         Close (Filter, Ignore_Error => True);
         Account_Exception (Result);
   end Decode_Tiny_Stream;

   procedure Decode_Tiny_Dictionary_Stream
     (Result     : in out Fuzz_Result;
      Input      : Byte_Array;
      Expected   : Byte_Array;
      Dictionary : Byte_Array) is
      Filter      : Filter_Type;
      Stream      : constant Ada.Streams.Stream_Element_Array := To_Stream (Input);
      In_Last     : Ada.Streams.Stream_Element_Offset;
      Out_Last    : Ada.Streams.Stream_Element_Offset;
      Output      : Ada.Streams.Stream_Element_Array (1 .. 1);
      Decoded     : Byte_Array (0 .. Expected'Length + 8);
      Decoded_Len : Natural := 0;
      First       : Ada.Streams.Stream_Element_Offset := Stream'First;
      Loops       : Natural := 0;

      procedure Capture_Output is
      begin
         if Out_Last >= Output'First
           and then Decoded_Len <= Decoded'Last
         then
            Decoded (Decoded_Len) := Byte (Output (Output'First));
            Decoded_Len := Decoded_Len + 1;
         end if;
      end Capture_Output;
   begin
      Inflate_Init (Filter, Zlib_Header);
      Inflate_Set_Dictionary (Filter, Dictionary);

      while First <= Stream'Last
        and then not Stream_End (Filter)
        and then Loops < 768
      loop
         Translate
           (Filter, Stream (First .. First), In_Last, Output, Out_Last,
            (if First = Stream'Last then Finish else No_Flush));
         Capture_Output;

         if In_Last >= First then
            First := In_Last + 1;
         else
            Flush (Filter, Output, Out_Last, No_Flush);
            Capture_Output;
         end if;
         Loops := Loops + 1;
      end loop;

      while not Stream_End (Filter) and then Loops < 768 loop
         Flush (Filter, Output, Out_Last, Finish);
         Capture_Output;
         Loops := Loops + 1;
      end loop;

      Close (Filter, Ignore_Error => True);
      Result.Digest := Result.Digest + Interfaces.Unsigned_32 (Dictionary'Length);

      if Loops >= 768 then
         Account (Result, Unexpected_End_Of_Input);
      elsif Decoded_Len = Expected'Length then
         if Expected'Length = 0 then
            Account (Result, Ok);
         elsif Decoded (0 .. Decoded_Len - 1) = Expected then
            Account (Result, Ok);
         else
            Account (Result, Invalid_Checksum);
         end if;
      else
         Account (Result, Invalid_Checksum);
      end if;
   exception
      when Zlib_Error | Status_Error =>
         Close (Filter, Ignore_Error => True);
         Account (Result, Invalid_Block_Type);
      when others =>
         Close (Filter, Ignore_Error => True);
         Account_Exception (Result);
   end Decode_Tiny_Dictionary_Stream;

   procedure Tiny_Buffer_Once
     (Result : in out Fuzz_Result;
      Seed   : in out Interfaces.Unsigned_32) is
      Payload  : constant Byte_Array := Patterned_Bytes (Seed, 96);
      Mode     : constant Compression_Mode :=
        Compression_Mode'Val
          (Pick
             (Seed, Compression_Mode'Pos (Compression_Mode'Last) + 1));
      Scenario : constant Natural := Pick (Seed, 5);
      CStat    : Status_Code;
   begin
      Note_Input (Result, Payload);
      case Scenario is
         when 0 =>
            declare
               Compressed : constant Byte_Array := Deflate_Raw (Payload, Mode, CStat);
            begin
               if CStat = Ok then
                  Decode_Tiny_Stream (Result, Compressed, Payload, Raw_Deflate);
               else
                  Account (Result, CStat);
               end if;
            end;
         when 1 =>
            declare
               Compressed : constant Byte_Array := Deflate (Payload, Dynamic, CStat);
            begin
               if CStat = Ok then
                  Decode_Tiny_Stream (Result, Compressed, Payload, Zlib_Header);
               else
                  Account (Result, CStat);
               end if;
            end;
         when 2 =>
            declare
               Metadata : GZip_Metadata := No_GZip_Metadata;
            begin
               Set_Name (Metadata, Random_Text (Seed, Pick (Seed, 12) + 1));
               Set_Comment (Metadata, Random_Text (Seed, Pick (Seed, 20) + 1));
               Set_Extra (Metadata, Random_Bytes (Seed, Pick (Seed, 24)));
               Set_Header_CRC (Metadata, True);
               declare
                  Compressed : constant Byte_Array :=
                    GZip (Payload, Mode, Metadata, CStat);
               begin
                  if CStat = Ok then
                     Decode_Tiny_Stream (Result, Compressed, Payload, GZip);
                  else
                     Account (Result, CStat);
                  end if;
               end;
            end;
         when 3 =>
            declare
               Tail_Payload : constant Byte_Array :=
                 Random_Bytes (Seed, Pick (Seed, 48));
               Head         : constant Byte_Array := GZip (Payload, Mode, CStat);
            begin
               if CStat /= Ok then
                  Account (Result, CStat);
               else
                  declare
                     Tail   : constant Byte_Array :=
                       GZip (Tail_Payload, Mode, CStat);
                     Joined : constant Byte_Array := Head & Tail;
                  begin
                     if CStat = Ok then
                        Decode_Tiny_Stream
                          (Result, Joined, Payload & Tail_Payload,
                           GZip, Multi_Member);
                     else
                        Account (Result, CStat);
                     end if;
                  end;
               end if;
            end;
         when others =>
            declare
               Dict       : constant Byte_Array :=
                 Random_Bytes (Seed, Pick (Seed, 24) + 1);
               Compressed : constant Byte_Array :=
                 Deflate_With_Dictionary (Payload, Dict, Mode, CStat);
            begin
               if CStat /= Ok then
                  Account (Result, CStat);
               else
                  Decode_Tiny_Dictionary_Stream
                    (Result, Compressed, Payload, Dict);
               end if;
            end;
      end case;
   end Tiny_Buffer_Once;

   procedure Lifecycle_Once
     (Result : in out Fuzz_Result) is
      IFlt : Filter_Type;
      CFlt : Compression_Filter_Type;
      In_Last  : Ada.Streams.Stream_Element_Offset;
      Out_Last : Ada.Streams.Stream_Element_Offset;
      Empty     : Ada.Streams.Stream_Element_Array (1 .. 0);
      One       : Ada.Streams.Stream_Element_Array (1 .. 1) := [others => 0];
      One_Input : constant Ada.Streams.Stream_Element_Array (1 .. 1) := [others => 16#41#];
   begin
      begin
         Translate (IFlt, Empty, In_Last, One, Out_Last, No_Flush);
         Account (Result, Invalid_Block_Type);
      exception
         when Status_Error => Account (Result, Ok);
         when others => Account_Exception (Result);
      end;

      begin
         Compress (CFlt, Empty, In_Last, One, Out_Last, No_Flush);
         Account (Result, Invalid_Block_Type);
      exception
         when Status_Error => Account (Result, Ok);
         when others => Account_Exception (Result);
      end;

      Inflate_Init (IFlt, Zlib_Header);
      Close (IFlt, Ignore_Error => True);
      begin
         Flush (IFlt, One, Out_Last, Finish);
         Account (Result, Invalid_Block_Type);
      exception
         when Status_Error => Account (Result, Ok);
         when others => Account_Exception (Result);
      end;

      begin
         Close (IFlt);
         Account (Result, Invalid_Block_Type);
      exception
         when Status_Error => Account (Result, Ok);
         when others => Account_Exception (Result);
      end;

      Deflate_Init (CFlt, Zlib_Header, Fixed);
      begin
         Compress (CFlt, One_Input, In_Last, One, Out_Last, No_Flush);
         Deflate_Set_Dictionary (CFlt, [0 => 16#41#]);
         Account (Result, Invalid_Block_Type);
      exception
         when Status_Error => Account (Result, Ok);
         when others => Account_Exception (Result);
      end;
      Compress_Close (CFlt, Ignore_Error => True);

      Deflate_Init (CFlt, Raw_Deflate, Stored);
      begin
         Compress (CFlt, Empty, In_Last, One, Out_Last, Finish);
         declare
            Guard : Natural := 0;
         begin
            while not Compress_Stream_End (CFlt) and then Guard < 64 loop
               Compress_Flush (CFlt, One, Out_Last, Finish);
               Guard := Guard + 1;
            end loop;
         end;

         if Compress_Stream_End (CFlt) then
            begin
               Compress_Flush (CFlt, One, Out_Last, Sync_Flush);
               Account (Result, Invalid_Block_Type);
            exception
               when Status_Error => Account (Result, Ok);
               when others => Account_Exception (Result);
            end;

            begin
               Compress_Flush (CFlt, One, Out_Last, Full_Flush);
               Account (Result, Invalid_Block_Type);
            exception
               when Status_Error => Account (Result, Ok);
               when others => Account_Exception (Result);
            end;
         else
            Account (Result, Unexpected_End_Of_Input);
         end if;
      exception
         when others => Account_Exception (Result);
      end;
      Compress_Close (CFlt, Ignore_Error => True);

      begin
         Compress_Close (CFlt);
         Account (Result, Invalid_Block_Type);
      exception
         when Status_Error => Account (Result, Ok);
         when others => Account_Exception (Result);
      end;
   end Lifecycle_Once;

   function Run
     (Target     : Target_Kind;
      Seed       : Interfaces.Unsigned_32;
      Iterations : Natural)
      return Fuzz_Result is
      S      : Interfaces.Unsigned_32 := Seed;
      Result : Fuzz_Result;
   begin
      for I in 1 .. Iterations loop
         case Target is
            when Inflate_Target =>
               Fuzz_Inflate_Once
                 (Result, S,
                  Header_Type'Val
                    (Pick (S, Header_Type'Pos (Header_Type'Last) + 1)));
            when Streaming_Inflate_Target =>
               Fuzz_Streaming_Inflate_Once
                 (Result, S,
                  Header_Type'Val (Pick (S, Header_Type'Pos (Header_Type'Last) + 1)));
            when Compress_Roundtrip_Target =>
               Roundtrip
                 (Result, S,
                  (case Pick (S, 3) is
                     when 0      => Zlib_Header,
                     when 1      => GZip,
                     when others => Raw_Deflate),
                  Compression_Mode'Val
                    (Pick
                       (S, Compression_Mode'Pos (Compression_Mode'Last) + 1)));
            when Wrapper_Mix_Target =>
               Wrapper_Mix_Once (Result, S);
            when Compression_Level_Target =>
               Level_Roundtrip_Once (Result, S);
            when Dictionary_Target =>
               Dictionary_Once (Result, S);
            when GZip_Metadata_Target =>
               GZip_Metadata_Once (Result, S);
            when Lifecycle_Target =>
               Lifecycle_Once (Result);
            when Mutation_Target =>
               Mutation_Once (Result, S);
            when Flush_Target =>
               Flush_Roundtrip_Once (Result, S);
            when Tiny_Buffer_Target =>
               Tiny_Buffer_Once (Result, S);
         end case;
         Result.Digest := Mix (Result.Digest, Byte (I mod 256));
      end loop;
      return Result;
   end Run;

   function Last_Hex_Snippet
     (Result : Fuzz_Result)
      return String is
   begin
      if Result.Last_Hex_Length = 0 then
         return "";
      end if;
      return Result.Last_Hex (1 .. Result.Last_Hex_Length);
   end Last_Hex_Snippet;

   function Expected_Failures_Are_Allowed
     (Target : Target_Kind)
      return Boolean
     with SPARK_Mode => On
   is
   begin
      return Target in Inflate_Target | Streaming_Inflate_Target | Mutation_Target;
   end Expected_Failures_Are_Allowed;

   function Acceptable
     (Target : Target_Kind;
      Result : Fuzz_Result)
      return Boolean
     with SPARK_Mode => On
   is
   begin
      return Result.Crashes = 0
        and then (Expected_Failures_Are_Allowed (Target) or else Result.Failures = 0);
   end Acceptable;

   function Same_Result
     (Left  : Fuzz_Result;
      Right : Fuzz_Result)
      return Boolean
     with SPARK_Mode => On
   is
   begin
      return Left.Runs = Right.Runs
        and then Left.Success = Right.Success
        and then Left.Failures = Right.Failures
        and then Left.Crashes = Right.Crashes
        and then Left.Digest = Right.Digest
        and then Left.Last_Input_Length = Right.Last_Input_Length
        and then Left.Last_Hex_Length = Right.Last_Hex_Length
        and then Left.Last_Hex = Right.Last_Hex;
   end Same_Result;
end Zlib.Fuzzing;
