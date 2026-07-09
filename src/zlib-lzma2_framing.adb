package body Zlib.LZMA2_Framing
  with SPARK_Mode => On
is

   function Decode_Control
     (Control : Byte;
      First   : Boolean) return Control_Info is
   begin
      if Control = 0 then
         return (Kind => End_Marker, others => False);
      elsif Control = 16#01# or else Control = 16#02# then
         if First and then Control /= 16#01# then
            return (Kind => Invalid, others => False);
         end if;

         return
           (Kind        => Uncompressed,
            Need_Props  => False,
            Reset_State => False,
            Reset_Dict  => Control = 16#01#);
      elsif Control >= 16#80# then
         return
           (Kind        => Compressed,
            Need_Props  => Control >= 16#C0#,
            Reset_State => Control >= 16#A0#,
            Reset_Dict  => Control >= 16#E0#);
      else
         return (Kind => Invalid, others => False);
      end if;
   end Decode_Control;

   function Uncompressed_Size (Hi, Lo : Byte) return Natural is
     (Natural (Hi) * 256 + Natural (Lo) + 1);

   function Compressed_Unpacked_Size (Control, Hi, Lo : Byte) return Natural is
     (Natural (Control and 16#1F#) * 65_536 + Natural (Hi) * 256 + Natural (Lo) + 1);

   function Packed_Size (Hi, Lo : Byte) return Natural is
     (Natural (Hi) * 256 + Natural (Lo) + 1);

   function Uncompressed_Chunk
     (Chunk : Byte_Array;
      First : Boolean) return Byte_Array
   is
      Stored : constant Natural := Chunk'Length - 1;
      Result : Byte_Array (1 .. Chunk'Length + 3) := [others => 0];
   begin
      Result (1) := (if First then 16#01# else 16#02#);
      Result (2) := Byte (Stored / 256);
      Result (3) := Byte (Stored mod 256);
      for I in Chunk'Range loop
         Result (4 + (I - Chunk'First)) := Chunk (I);
      end loop;
      return Result;
   end Uncompressed_Chunk;

   function Compressed_Chunk
     (Plain : Byte_Array;
      Coded : Byte_Array;
      Props : Byte) return Byte_Array
   is
      Unpacked_Size : constant Natural := Plain'Length - 1;
      Packed_Size   : constant Natural := Coded'Length - 1;
      Result        : Byte_Array (1 .. Coded'Length + 6) := [others => 0];
   begin
      Result (1) := Byte (16#E0# + Unpacked_Size / 65_536);
      Result (2) := Byte ((Unpacked_Size / 256) mod 256);
      Result (3) := Byte (Unpacked_Size mod 256);
      Result (4) := Byte (Packed_Size / 256);
      Result (5) := Byte (Packed_Size mod 256);
      Result (6) := Props;
      for I in Coded'Range loop
         Result (7 + (I - Coded'First)) := Coded (I);
      end loop;
      return Result;
   end Compressed_Chunk;

end Zlib.LZMA2_Framing;
