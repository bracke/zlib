--  Support level: private internal implementation.
--
--  Finding a ZIP archive's end of central directory record from the file's
--  tail, and with it the central directory's place, size and member count.
--  Both the seek-based extractor and the public Count_ZIP_File_Entries use
--  it, so a ZIP is recognised the same way whether it is listed, extracted
--  or only counted.
--
--  Also the little-endian field readers and the positioned read the ZIP file
--  readers share.
with Ada.Streams.Stream_IO;
with Interfaces;

package Zlib.ZIP_End_Records is

   type End_Record is record
      Found     : Boolean := False;
      --  A valid end record was found; the fields below describe it.
      Count     : Natural := 0;
      --  The member count the archive states, saturated at Natural'Last.
      Capped    : Boolean := False;
      --  The stated count was above Natural'Last.
      CD_Offset : Interfaces.Unsigned_64 := 0;
      --  The central directory's stated offset from the archive's start.
      CD_Size   : Interfaces.Unsigned_64 := 0;
      --  The central directory's stated size in bytes.
      Shifted   : Boolean := False;
      --  The ZIP64 record was found right before its locator rather than at
      --  the offset the locator states: data in front of the archive (a
      --  self-extracting stub) moved it, so CD_Offset is not a file
      --  position. The count is still the archive's own.
   end record;

   procedure Locate
     (File      : in out Ada.Streams.Stream_IO.File_Type;
      File_Size : Interfaces.Unsigned_64;
      Result    : out End_Record);
   --  Search the last 64 KiB and a record's worth of File backwards for the
   --  End Of Central Directory record (PK 5 6), and for a ZIP64 archive read
   --  the ZIP64 record (PK 6 6) its locator (PK 6 7) points to. The last
   --  record whose comment fits the file and whose central directory lies
   --  before it is taken: a PK 5 6 in a comment or in member data is passed
   --  over. A record whose count says "see the ZIP64 record" when that record
   --  cannot be found ends the search unfound: an earlier record would be a
   --  stored inner archive's.
   --  @param File archive file, open for reading
   --  @param File_Size the file's length in bytes
   --  @param Result what was found; Found False when there is no valid record

   function U16_At
     (Data : Byte_Array; Pos : Natural) return Interfaces.Unsigned_16;
   --  The little-endian 16-bit field at Data (Pos).
   --  @param Data bytes holding the field
   --  @param Pos index of the field's first byte
   --  @return the field's value

   function U32_At
     (Data : Byte_Array; Pos : Natural) return Interfaces.Unsigned_32;
   --  The little-endian 32-bit field at Data (Pos).
   --  @param Data bytes holding the field
   --  @param Pos index of the field's first byte
   --  @return the field's value

   function U64_At
     (Data : Byte_Array; Pos : Natural) return Interfaces.Unsigned_64;
   --  The little-endian 64-bit field at Data (Pos).
   --  @param Data bytes holding the field
   --  @param Pos index of the field's first byte
   --  @return the field's value

   procedure Read_At
     (File   : in out Ada.Streams.Stream_IO.File_Type;
      Offset : Interfaces.Unsigned_64;
      Into   : out Byte_Array;
      Ok     : out Boolean);
   --  Read Into'Length bytes of File starting at the 0-based Offset.
   --  @param File file open for reading
   --  @param Offset 0-based byte offset of the first byte
   --  @param Into receives the bytes (zeroed when the read falls short)
   --  @param Ok True when every byte was read

end Zlib.ZIP_End_Records;
