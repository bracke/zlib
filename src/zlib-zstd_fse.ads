with Interfaces;

with Zlib.Zstd_Bits;
with Zlib.Zstd_Tables;

package Zlib.Zstd_FSE is
   --  Support level: private internal implementation.
   --  zstd's finite state entropy coder (an ANS variant).
   --
   --  A table is described by a normalized count per symbol summing to 2**Log.
   --  Decoding walks a state through a spread table, emitting a symbol and
   --  reading a few bits per step; encoding runs the same machine backwards,
   --  which is why the payload is written and read in opposite directions.

   Max_Log    : constant Natural := 9;
   Max_Symbol : constant Natural := 255;

   subtype Log_Range is Natural range 5 .. Max_Log;

   type Decode_Table is private;
   type Encode_Table is private;

   procedure Read_Counts
     (Data       : Byte_Array;
      First      : Natural;
      Max_Code   : Natural;
      Counts     : out Zlib.Zstd_Tables.Count_Array;
      Log        : out Natural;
      Last_Code  : out Natural;
      Used       : out Natural;
      Status     : out Status_Code);
   --  Parse a table description: the accuracy log, then one normalized count per
   --  symbol, read forward and least-significant bit first.
   --  @param Data      the payload
   --  @param First     index of the description's first byte
   --  @param Max_Code  the largest symbol the caller allows
   --  @param Counts    the normalized counts; -1 marks a low-probability symbol
   --  @param Log       the accuracy log
   --  @param Last_Code the largest symbol actually present
   --  @param Used      bytes consumed
   --  @param Status    Ok, Invalid_Huffman_Code for a malformed description, or
   --                   Unexpected_End_Of_Input

   procedure Build_Decode
     (Counts   : Zlib.Zstd_Tables.Count_Array;
      Log      : Natural;
      Table    : out Decode_Table;
      Status   : out Status_Code);
   --  Build a decode table from normalized counts.
   --  @param Counts the normalized counts
   --  @param Log    the accuracy log
   --  @param Table  the resulting table
   --  @param Status Ok, or Invalid_Huffman_Code when the counts are inconsistent

   procedure Build_Encode
     (Counts : Zlib.Zstd_Tables.Count_Array;
      Log    : Natural;
      Table  : out Encode_Table;
      Status : out Status_Code);
   --  Build an encode table from the same normalized counts.
   --  @param Counts the normalized counts
   --  @param Log    the accuracy log
   --  @param Table  the resulting table
   --  @param Status Ok, or Invalid_Huffman_Code when the counts are inconsistent

   procedure Init_Decode
     (Table  : Decode_Table;
      R      : in out Zlib.Zstd_Bits.Backward_Reader;
      Data   : Byte_Array;
      State  : out Natural;
      Status : out Status_Code);
   --  Read the initial state: Log bits.
   --  @param Table  the decode table
   --  @param R      the payload reader
   --  @param Data   the payload
   --  @param State  the initial state
   --  @param Status Ok, or Unexpected_End_Of_Input

   function Symbol (Table : Decode_Table; State : Natural) return Natural;
   --  The symbol a state emits.
   --  @param Table the decode table
   --  @param State the current state
   --  @return the symbol

   procedure Advance
     (Table  : Decode_Table;
      R      : in out Zlib.Zstd_Bits.Backward_Reader;
      Data   : Byte_Array;
      State  : in out Natural;
      Status : out Status_Code);
   --  Step the state on, reading the bits this state calls for.
   --  @param Table  the decode table
   --  @param R      the payload reader
   --  @param Data   the payload
   --  @param State  the state, updated
   --  @param Status Ok, or Unexpected_End_Of_Input

   --  Encoding. The caller drives the machine in reverse: it starts the state at
   --  the LAST symbol it will encode, walks backwards, and flushes at the end.
   --  Bits therefore come out in reverse order, which is exactly what the
   --  backward reader undoes.

   procedure Init_Encode
     (Table  : Encode_Table;
      Symbol : Natural;
      State  : out Natural;
      W      : in out Zlib.Zstd_Bits.Backward_Writer);
   --  Start an encoding state on Symbol.
   --  @param Table  the encode table
   --  @param Symbol the first symbol encoded, i.e. the last one decoded
   --  @param State  the initial state
   --  @param W      the payload writer

   procedure Encode
     (Table  : Encode_Table;
      Symbol : Natural;
      State  : in out Natural;
      W      : in out Zlib.Zstd_Bits.Backward_Writer);
   --  Encode one symbol, emitting the bits the transition needs.
   --  @param Table  the encode table
   --  @param Symbol the symbol to encode
   --  @param State  the state, updated
   --  @param W      the payload writer

   procedure Flush_Encode
     (Table : Encode_Table;
      State : Natural;
      W     : in out Zlib.Zstd_Bits.Backward_Writer);
   --  Write the final state, which the decoder reads first.
   --  @param Table the encode table
   --  @param State the final state
   --  @param W     the payload writer

   function Log_Of (Table : Encode_Table) return Natural;
   --  The table's accuracy log.
   --  @param Table the encode table
   --  @return the log

   procedure Normalize
     (Frequencies : Zlib.Zstd_Tables.Value_Array;
      Total       : Natural;
      Max_Code    : Natural;
      Log         : Natural;
      Counts      : out Zlib.Zstd_Tables.Count_Array;
      Status      : out Status_Code);
   --  Scale raw frequencies to normalized counts summing to 2**Log, giving every
   --  present symbol at least one slot.
   --  @param Frequencies raw symbol counts
   --  @param Total       their sum
   --  @param Max_Code    the largest symbol
   --  @param Log         the accuracy log to hit
   --  @param Counts      the normalized counts
   --  @param Status      Ok, or Invalid_Huffman_Code when normalization fails

   procedure Write_Counts
     (Counts   : Zlib.Zstd_Tables.Count_Array;
      Log      : Natural;
      Max_Code : Natural;
      Output   : out Byte_Array;
      Length   : out Natural;
      Status   : out Status_Code);
   --  Emit a table description the decoder's Read_Counts will accept.
   --  @param Counts   the normalized counts
   --  @param Log      the accuracy log
   --  @param Max_Code the largest symbol
   --  @param Output   receives the description
   --  @param Length   bytes written
   --  @param Status   Ok, or Invalid_Huffman_Code when the counts are unusable

private

   Max_Table : constant Natural := 2 ** Max_Log;

   type Entry_Record is record
      Symbol     : Natural := 0;
      Bits       : Natural := 0;
      Next_State : Natural := 0;
   end record;

   type Entry_Array is array (0 .. Max_Table - 1) of Entry_Record;

   type Decode_Table is record
      Entries : Entry_Array;
      Log     : Natural := 0;
   end record;

   type Transform_Record is record
      Delta_Bits  : Integer := 0;
      Delta_State : Integer := 0;
   end record;

   type Transform_Array is array (0 .. Max_Symbol) of Transform_Record;
   type State_Array is array (0 .. Max_Table - 1) of Natural;

   type Encode_Table is record
      Transform : Transform_Array;
      States    : State_Array;
      Log       : Natural := 0;
   end record;

   use type Interfaces.Unsigned_32;

end Zlib.Zstd_FSE;
