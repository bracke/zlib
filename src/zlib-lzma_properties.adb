package body Zlib.LZMA_Properties
  with SPARK_Mode => On
is

   function Valid_Props (Props : Byte) return Boolean is
      Props_Value : constant Natural := Natural (Props);
      LCLP        : constant Natural := Props_Value mod 9;
      Rest        : constant Natural := Props_Value / 9;
      LC          : constant Natural := LCLP;
      LP          : constant Natural := Rest mod 5;
      PB          : constant Natural := Rest / 5;
   begin
      return LC <= 8 and then LP <= 4 and then PB <= 4 and then LC + LP <= 4;
   end Valid_Props;

   function Props_Byte
     (LC, LP, PB : Natural) return Byte
   is
   begin
      return Byte ((PB * 5 + LP) * 9 + LC);
   end Props_Byte;

   function Default_Dict_Properties
     (Props : Byte) return LZMA_Properties
   is
      Dict : constant Natural := Natural (Default_Dict);
   begin
      return
        [1 => Props,
         2 => Byte (Dict mod 256),
         3 => Byte ((Dict / 256) mod 256),
         4 => Byte ((Dict / 65_536) mod 256),
         5 => Byte ((Dict / 16#0100_0000#) mod 256)];
   end Default_Dict_Properties;

   function Raw_Stream_Header
     (Props : LZMA_Properties) return LZMA_Raw_Header
   is
   begin
      return
        [1 => 0,
         2 => 0,
         3 => 5,
         4 => 0,
         5 => Props (1),
         6 => Props (2),
         7 => Props (3),
         8 => Props (4),
         9 => Props (5)];
   end Raw_Stream_Header;

end Zlib.LZMA_Properties;
