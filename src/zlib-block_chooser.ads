with Zlib.LZ77_Matcher;

package Zlib.Block_Chooser is
   --  Support level: private internal implementation.
   --  Internal deterministic Deflate block scorer used by Auto compression.
   --  Scores are Deflate payload bit counts only; zlib/gzip/raw wrapper and
   --  trailer bytes are intentionally excluded so block choice is
   --  wrapper-independent.

   type Block_Kind is (Stored_Block, Fixed_Block, Dynamic_Block);

   type Candidate_Score is record
      Kind  : Block_Kind := Stored_Block;
      Valid : Boolean := False;
      Bits  : Natural := 0;
   end record;

   function Stored_Bit_Size
     (Payload_Length     : Natural;
      Starting_Bit_Index : Natural := 0)
      return Natural;
   --  Return the bit size of one or more stored Deflate blocks, including
   --  block header bits, byte-alignment padding, LEN/NLEN, and data bytes.
   --  @param Payload_Length Payload_Length argument supplied to Stored_Bit_Size
   --  @param Starting_Bit_Index Starting_Bit_Index argument supplied to Stored_Bit_Size
   --  @return result produced by Stored_Bit_Size
   function Fixed_Bit_Size
     (Tokens             : Zlib.LZ77_Matcher.Token_Array;
      Starting_Bit_Index : Natural := 0)
      return Candidate_Score;
   --  Return fixed-Huffman candidate size including block header, token bits,
   --  extra bits, EOB, and final byte padding.
   --  @param Tokens Tokens argument supplied to Fixed_Bit_Size
   --  @param Starting_Bit_Index Starting_Bit_Index argument supplied to Fixed_Bit_Size
   --  @return result produced by Fixed_Bit_Size
   function Dynamic_Bit_Size
     (Tokens             : Zlib.LZ77_Matcher.Token_Array;
      Starting_Bit_Index : Natural := 0)
      return Candidate_Score;
   --  Return dynamic-Huffman candidate size including dynamic header cost,
   --  encoded code lengths, token payload, extra bits, EOB, and final byte
   --  padding. Invalid dynamic construction returns Valid => False.
   --  @param Tokens Tokens argument supplied to Dynamic_Bit_Size
   --  @param Starting_Bit_Index Starting_Bit_Index argument supplied to Dynamic_Bit_Size
   --  @return result produced by Dynamic_Bit_Size
   function Choose_From_Scores
     (Stored_Candidate  : Candidate_Score;
      Fixed_Candidate   : Candidate_Score;
      Dynamic_Candidate : Candidate_Score)
      return Candidate_Score;
   --  Choose from precomputed candidates using the public Auto tie-breaker.
   --  This is exposed for deterministic scorer tests and remains an internal
   --  child-package API.
   --  @param Stored_Candidate Stored_Candidate argument supplied to Choose_From_Scores
   --  @param Fixed_Candidate Fixed_Candidate argument supplied to Choose_From_Scores
   --  @param Dynamic_Candidate Dynamic_Candidate argument supplied to Choose_From_Scores
   --  @return result produced by Choose_From_Scores
   function Choose
     (Input              : Byte_Array;
      Level              : Compression_Level := Default_Level;
      Allow_Dynamic      : Boolean := True;
      Allow_Stored       : Boolean := True;
      Starting_Bit_Index : Natural := 0)
      return Candidate_Score;
   --  Choose the smallest valid block candidate. Equal bit counts use the
   --  deterministic tie-breaker Stored, then Fixed, then Dynamic. Allow_Stored
   --  may be False when the current streaming bit position cannot be handed to
   --  the byte-oriented stored-block emitter.
   --  @param Input Input argument supplied to Choose
   --  @param Level Level argument supplied to Choose
   --  @param Allow_Dynamic Allow_Dynamic argument supplied to Choose
   --  @param Allow_Stored Allow_Stored argument supplied to Choose
   --  @param Starting_Bit_Index Starting_Bit_Index argument supplied to Choose
   --  @return result produced by Choose
   function To_Mode (Kind : Block_Kind) return Compression_Mode;
   --  Return the To Mode result.
   --  @param Kind Kind argument supplied to To_Mode
   --  @return result produced by To_Mode

end Zlib.Block_Chooser;
