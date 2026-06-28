with Interfaces; use Interfaces;
package body Zlib.Wrapper is

   function To_U32
     (B : Zlib.Byte)
      return Interfaces.Unsigned_32
   is
   begin
      return Interfaces.Unsigned_32 (B);
   end To_U32;

   procedure Parse
     (Input  : Zlib.Byte_Array;
      Info   : out Zlib_Stream_Info;
      Status : out Zlib.Status_Code)
   is
      CMF          : Zlib.Byte;
      FLG          : Zlib.Byte;
      Method       : Natural;
      CInfo        : Natural;
      Header_Value : Natural;
      Last         : Natural;
   begin
      Info := (Deflate_First  => 0,
               Deflate_Last   => 0,
               Expected_Adler => 0);

      if Input'Length < 6 then
         Status := Zlib.Unexpected_End_Of_Input;
         return;
      end if;

      CMF := Input (Input'First);
      FLG := Input (Input'First + 1);

      Method := Natural (CMF and 16#0F#);
      CInfo  := Natural (CMF / 16);

      if Method /= 8 then
         Status := Zlib.Unsupported_Method;
         return;
      end if;

      if CInfo > 7 then
         Status := Zlib.Invalid_Header;
         return;
      end if;

      Header_Value := Natural (CMF) * 256 + Natural (FLG);

      if Header_Value mod 31 /= 0 then
         Status := Zlib.Invalid_Header;
         return;
      end if;

      pragma Assert
        (Header_Value mod 31 = 0,
         "zlib header checksum invariant broken");

      if (FLG and 16#20#) /= 0 then
         Status := Zlib.Unsupported_Preset_Dictionary;
         return;
      end if;

      Last := Input'Last;

      Info.Deflate_First := Input'First + 2;
      Info.Deflate_Last  := Last - 4;

      Info.Expected_Adler :=
        Interfaces.Shift_Left (To_U32 (Input (Last - 3)), 24) or
        Interfaces.Shift_Left (To_U32 (Input (Last - 2)), 16) or
        Interfaces.Shift_Left (To_U32 (Input (Last - 1)), 8) or
        To_U32 (Input (Last));

      Status := Zlib.Ok;
   end Parse;

end Zlib.Wrapper;
