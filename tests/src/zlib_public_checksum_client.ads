with Zlib;

package Zlib_Public_Checksum_Client is
   --  Compile-contract fixture: this package intentionally depends only on
   --  the root Zlib package. It must not with internal checksum children.

   subtype Root_Byte is Zlib.Byte;
   --  Keep the root Zlib dependency visible in the spec.

   function Checksums_Are_Available return Boolean;
   --  Return the Checksums Are Available result.
   --  @return result produced by Checksums_Are_Available

end Zlib_Public_Checksum_Client;
