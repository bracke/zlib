with Ada.Streams;

package Zlib.Sliding_Window is
   --  Support level: private internal implementation.
   --  Internal bounded output/history state for streaming Deflate
   --  decoding. The window stores the 32 KiB LZ77 history and a bounded
   --  pending-output queue that can be drained into caller-owned buffers.

   type Window is private;
   --  Combined LZ77 history and pending-output queue.

   type Write_Status is
     (Ok,
      Need_Output,
      Invalid_Distance,
      Invalid_Length);
   --  Result of writing literal or match-copy output.

   procedure Reset
     (W : in out Window);
   --  Clear history, pending output, and active match-copy state.
   --  @param W W argument supplied to Reset
   procedure Seed
     (W    : in out Window;
      Data : Ada.Streams.Stream_Element_Array);
   --  Seed the LZ77 history with the trailing 32 KiB of a preset
   --  dictionary. Seed bytes are history only; they are not pending output
   --  and do not contribute to Total_Output.
   --  @param W W argument supplied to Seed
   --  @param Data Data argument supplied to Seed
   function Total_Output
     (W : Window)
      return Natural
     with SPARK_Mode => On;
   --  Return total decoded bytes accepted into the window.
   --  @param W W argument supplied to Total_Output
   --  @return result produced by Total_Output
   function Pending_Output
     (W : Window)
      return Natural
     with SPARK_Mode => On;
   --  Return bytes waiting to be drained by the public API.
   --  @param W W argument supplied to Pending_Output
   --  @return result produced by Pending_Output
   procedure Put_Byte
     (W      : in out Window;
      B      : Ada.Streams.Stream_Element;
      Status : out Write_Status);
   --  Append one decoded literal byte to history and pending output.
   --  @param W W argument supplied to Put_Byte
   --  @param B B argument supplied to Put_Byte
   --  @param Status Status argument supplied to Put_Byte
   procedure Begin_Copy
     (W        : in out Window;
      Length   : Natural;
      Distance : Natural;
      Status   : out Write_Status);
   --  Validate and start an LZ77 match copy.
   --  @param W W argument supplied to Begin_Copy
   --  @param Length Length argument supplied to Begin_Copy
   --  @param Distance Distance argument supplied to Begin_Copy
   --  @param Status Status argument supplied to Begin_Copy
   procedure Emit_Copy_Byte
     (W      : in out Window;
      B      : out Ada.Streams.Stream_Element;
      Status : out Write_Status);
   --  Emit the next byte from the active match copy.
   --  @param W W argument supplied to Emit_Copy_Byte
   --  @param B B argument supplied to Emit_Copy_Byte
   --  @param Status Status argument supplied to Emit_Copy_Byte
   procedure Start_Copy
     (W        : in out Window;
      Length   : Natural;
      Distance : Natural;
      Status   : out Write_Status);
   --  Start a match copy and emit as much as pending capacity allows.
   --  @param W W argument supplied to Start_Copy
   --  @param Length Length argument supplied to Start_Copy
   --  @param Distance Distance argument supplied to Start_Copy
   --  @param Status Status argument supplied to Start_Copy
   procedure Continue_Copy
     (W      : in out Window;
      Status : out Write_Status);
   --  Continue an active match copy after output has been drained.
   --  @param W W argument supplied to Continue_Copy
   --  @param Status Status argument supplied to Continue_Copy
   procedure Drain
     (W        : in out Window;
      Out_Data : out Ada.Streams.Stream_Element_Array;
      Out_Last : out Ada.Streams.Stream_Element_Offset);
   --  Drain pending output into an empty caller output buffer.
   --  @param W W argument supplied to Drain
   --  @param Out_Data Out_Data argument supplied to Drain
   --  @param Out_Last Out_Last argument supplied to Drain
   procedure Drain_Append
     (W        : in out Window;
      Out_Data : in out Ada.Streams.Stream_Element_Array;
      Out_Last : in out Ada.Streams.Stream_Element_Offset);
   --  Append drained pending output after bytes already written to Out_Data.
   --  @param W W argument supplied to Drain_Append
   --  @param Out_Data Out_Data argument supplied to Drain_Append
   --  @param Out_Last Out_Last argument supplied to Drain_Append
   function Copy_Active
     (W : Window)
      return Boolean
     with SPARK_Mode => On;
   --  Return True while an LZ77 match copy still has bytes remaining.
   --  @param W W argument supplied to Copy_Active
   --  @return result produced by Copy_Active
private
   Window_Size      : constant Natural := 32 * 1024;
   Pending_Capacity : constant Natural := 64;

   subtype History_Index is Natural range 0 .. Window_Size - 1;
   subtype Pending_Index is Natural range 0 .. Pending_Capacity - 1;

   type History_Buffer is array (History_Index) of Ada.Streams.Stream_Element;
   type Pending_Buffer is array (Pending_Index) of Ada.Streams.Stream_Element;

   type Window is record
      History       : History_Buffer := [others => 0];
      History_Next  : History_Index := 0;
      History_Count : Natural range 0 .. Window_Size := 0;

      Pending       : Pending_Buffer := [others => 0];
      Pending_First : Pending_Index := 0;
      Pending_Count : Natural range 0 .. Pending_Capacity := 0;

      Total         : Natural := 0;

      Copy_Remaining : Natural range 0 .. 258 := 0;
      Copy_Distance  : Natural range 0 .. Window_Size := 0;
   end record;
end Zlib.Sliding_Window;
