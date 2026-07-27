--  Support level: private internal implementation.
--
--  Seek-based ZIP extraction. The central directory is read from the archive
--  file and each member is then streamed from that file straight to its output
--  file, so working memory is bounded by the fixed chunk buffers rather than by
--  the archive size or by the size of any one member.
--
--  A ZIP cannot be decoded front to back: the central directory lives at the
--  end of the file. This package therefore seeks rather than streaming
--  sequentially, which is why it takes a path instead of an input stream.

package Zlib.ZIP_Streaming_Extraction is
   pragma Elaborate_Body;

   procedure Extract_To_Directory
     (Archive_Path    : String;
      Destination_Dir : String;
      Safe_Entry_Name : not null access function
        (Entry_Name : String) return Boolean;
      Handled         : out Boolean;
      Status          : out Status_Code);
   --  Extract every member of the ZIP at Archive_Path below Destination_Dir,
   --  creating subdirectories and recreating directory entries.
   --
   --  Handled is False when the archive needs something this package does not
   --  stream: a member whose method is neither Stored nor Deflate, an
   --  encrypted member, or a container this reader does not recognize. The
   --  caller must then fall back to whole-image extraction, and Status carries
   --  no meaning. When Handled is True, Status is the deterministic result.
   --  @param Archive_Path path to the .zip file
   --  @param Destination_Dir directory to extract into
   --  @param Safe_Entry_Name predicate rejecting unsafe relative entry paths
   --  @param Handled False when the caller must fall back to whole-image
   --  extraction
   --  @param Status Ok on success, otherwise a deterministic failure code

end Zlib.ZIP_Streaming_Extraction;
