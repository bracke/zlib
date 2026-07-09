with Zlib.LZMA_Decoder;

package body Zlib.LZMA_Raw is

   function Decode
     (Stream    : Byte_Array;
      Props     : Zlib.LZMA_Properties.LZMA_Properties;
      Plain_Len : Natural;
      Status    : out Status_Code) return Byte_Array
   is
   begin
      return Decode_With
        (Stream, Props, Plain_Len,
         Require_Full_Stream => True,
         Initial_Rep_Distance => 1,
         Use_Matched_Literals => True,
         Status => Status);
   end Decode;

   function Decode_With
     (Stream               : Byte_Array;
      Props                : Zlib.LZMA_Properties.LZMA_Properties;
      Plain_Len            : Natural;
      Require_Full_Stream  : Boolean;
      Initial_Rep_Distance : Natural;
      Use_Matched_Literals : Boolean;
      Status               : out Status_Code) return Byte_Array
   is
      Prefix : constant Zlib.LZMA_Properties.LZMA_Raw_Header :=
        Zlib.LZMA_Properties.Raw_Stream_Header (Props);
      Header : Byte_Array (1 .. Prefix'Length + Stream'Length);
      Out_I  : Natural := Header'First;
   begin
      for B of Prefix loop
         Header (Out_I) := B;
         Out_I := Out_I + 1;
      end loop;
      for B of Stream loop
         Header (Out_I) := B;
         Out_I := Out_I + 1;
      end loop;

      return Zlib.LZMA_Decoder.Decode_Payload
        (Header, Plain_Len,
         Require_Full_Stream => Require_Full_Stream,
         Initial_Rep_Distance => Initial_Rep_Distance,
         Use_Matched_Literals => Use_Matched_Literals,
         Status => Status);
   end Decode_With;

   function Decode_Encoded_Header
     (Stream    : Byte_Array;
      Props     : Zlib.LZMA_Properties.LZMA_Properties;
      Plain_Len : Natural;
      Status    : out Status_Code) return Byte_Array
   is
      Local_Status  : Status_Code := Ok;
      Strict_Result : constant Byte_Array :=
        Decode_With
          (Stream, Props, Plain_Len,
           Require_Full_Stream => True,
           Initial_Rep_Distance => 1,
           Use_Matched_Literals => True,
           Status => Local_Status);
   begin
      if Local_Status = Ok then
         Status := Ok;
         return Strict_Result;
      end if;

      return Decode_With
        (Stream, Props, Plain_Len,
         Require_Full_Stream => False,
         Initial_Rep_Distance => 1,
         Use_Matched_Literals => True,
         Status => Status);
   end Decode_Encoded_Header;

end Zlib.LZMA_Raw;
