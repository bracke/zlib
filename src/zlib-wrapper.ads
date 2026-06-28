with Interfaces;

package Zlib.Wrapper is
   --  Support level: private internal implementation.
   --  Legacy internal parser for complete zlib wrappers.
   --
   --  The public one-shot path now uses the streaming engine. This package is
   --  retained for focused wrapper tests and maintenance comparison only.

   type Zlib_Stream_Info is record
      Deflate_First  : Natural := 0;
      Deflate_Last   : Natural := 0;
      Expected_Adler : Interfaces.Unsigned_32 := 0;
   end record;
   --  Location of the wrapped Deflate payload and expected checksum.

   procedure Parse
     (Input  : Zlib.Byte_Array;
      Info   : out Zlib_Stream_Info;
      Status : out Zlib.Status_Code);
   --  Validate a zlib wrapper and expose its payload range and footer.
   --  @param Input complete zlib stream
   --  @param Info parsed payload bounds and expected Adler-32
   --  @param Status set to Ok or a wrapper validation failure
end Zlib.Wrapper;
