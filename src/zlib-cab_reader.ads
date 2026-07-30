--  Support level: private internal implementation.
--
--  Microsoft Cabinet (.cab / MSCF) reader. Lists the members of a cabinet and
--  extracts a member's bytes, decompressing an MSZIP folder (MSZIP is raw
--  Deflate behind a two-byte 'CK' block signature). Only the single-folder,
--  single-CFDATA-block layout with Store or MSZIP compression is handled; any
--  other layout (multiple folders or blocks, reserved fields, LZX/Quantum)
--  fails closed. The root Zlib package is the sole public entry point.
package Zlib.Cab_Reader is

   function List_Entries
     (Archive_Image : Byte_Array;
      Status        : out Status_Code) return Archive_Entry_Array;

   function Extract_Entry
     (Archive_Image : Byte_Array;
      Entry_Name    : String;
      Status        : out Status_Code) return Byte_Array;

end Zlib.Cab_Reader;
