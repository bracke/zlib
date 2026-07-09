package body Zlib.Seven_Zip_Coders is
   use type Interfaces.Unsigned_32;
   use type Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;

   Empty_Bytes : constant Byte_Array (1 .. 0) := [others => 0];

   function Build_Descriptor
     (Method : Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;
      Props  : Byte_Array) return Byte_Array
   is
      use Zlib.Seven_Zip_Methods;

      Desc       : constant Seven_Zip_Coder_Descriptor := Descriptor (Method);
      Has_Counts : constant Boolean := Desc.Input_Count /= 1 or else Desc.Output_Count /= 1;
      Length     : constant Natural :=
        1 + Desc.ID_Length
        + (if Has_Counts then 2 else 0)
        + (if Props'Length > 0 then 1 + Props'Length else 0);
      Result     : Byte_Array (1 .. Length);
      Pos        : Natural := Result'First;
   begin
      Result (Pos) := Descriptor_Flags (Method, Props'Length > 0);
      Pos := Pos + 1;

      for B of Desc.ID loop
         Result (Pos) := B;
         Pos := Pos + 1;
      end loop;

      if Has_Counts then
         Result (Pos) := Byte (Desc.Input_Count);
         Pos := Pos + 1;
         Result (Pos) := Byte (Desc.Output_Count);
         Pos := Pos + 1;
      end if;

      if Props'Length > 0 then
         Result (Pos) := Byte (Props'Length);
         Pos := Pos + 1;
         for B of Props loop
            Result (Pos) := B;
            Pos := Pos + 1;
         end loop;
      end if;

      return Result;
   end Build_Descriptor;

   function Descriptor_Bytes
     (Method     : Zlib.Seven_Zip_Methods.Seven_Zip_Coder_Method;
      LZMA_Props : Byte := Zlib.LZMA_Properties.Default_Props) return Byte_Array
   is
      use Zlib.Seven_Zip_Methods;
   begin
      case Method is
         when Seven_Zip_LZMA_Method =>
            return Build_Descriptor
              (Method, Zlib.LZMA_Properties.Default_Dict_Properties (LZMA_Props));

         when Seven_Zip_LZMA2_Method =>
            return Build_Descriptor (Method, [1 => 16#16#]);

         when Seven_Zip_Delta_Method =>
            return Delta_Descriptor_Bytes (1);

         when Seven_Zip_PPMd_Method =>
            return Build_Descriptor
              (Method,
               [Byte (PPMd_Default_Order),
                Byte (PPMd_Default_Memory mod 256),
                Byte ((PPMd_Default_Memory / 256) mod 256),
                Byte ((PPMd_Default_Memory / 65_536) mod 256),
                Byte ((PPMd_Default_Memory / 16#0100_0000#) mod 256)]);

         when Seven_Zip_AES_Method =>
            return Empty_Bytes;

         when others =>
            return Build_Descriptor (Method, Empty_Bytes);
      end case;
   end Descriptor_Bytes;

   function Delta_Descriptor_Bytes (Distance : Positive) return Byte_Array is
   begin
      if Distance > 256 then
         return Empty_Bytes;
      end if;

      return
        Build_Descriptor
          (Zlib.Seven_Zip_Methods.Seven_Zip_Delta_Method,
           [1 => Byte (Distance - 1)]);
   end Delta_Descriptor_Bytes;

   function AES_Descriptor_Bytes
     (IV               : Byte_Array;
      Num_Cycles_Power : Natural := 19) return Byte_Array
   is
      Props : Byte_Array (1 .. 2 + IV'Length);
      Pos   : Natural := Props'First;
   begin
      if IV'Length /= 16 or else Num_Cycles_Power > 63 then
         return Empty_Bytes;
      end if;

      Props (Pos) := Byte (16#40# + Num_Cycles_Power);
      Pos := Pos + 1;
      Props (Pos) := Byte (IV'Length - 1);
      Pos := Pos + 1;
      for B of IV loop
         Props (Pos) := B;
         Pos := Pos + 1;
      end loop;

      return
        Build_Descriptor
          (Zlib.Seven_Zip_Methods.Seven_Zip_AES_Method, Props);
   end AES_Descriptor_Bytes;

end Zlib.Seven_Zip_Coders;
