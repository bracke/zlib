with Ada.Calendar; use Ada.Calendar;
with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Zlib; use Zlib;
with Zlib_Bench_Support;

procedure Zlib_Bench_Inflate is
   package CLI renames Ada.Command_Line;
   package TIO renames Ada.Text_IO;
   use Ada.Strings.Unbounded;
   use Zlib_Bench_Support;

   Config     : Inflate_Config;
   Input_Path : Unbounded_String;
   Have_Input : Boolean := False;
   Status     : Zlib.Status_Code;

   procedure Usage is
   begin
      TIO.Put_Line ("usage: zlib_bench_inflate --input FILE --wrapper zlib|gzip|raw");
      TIO.Put_Line
        ("       [--input-chunk BYTES] [--output-chunk BYTES] [--repeat N] [--expect-size BYTES]");
      TIO.Put_Line ("       all value options also accept --name=value form");
   end Usage;

   function Need_Value
     (Index : in out Natural;
      Name  : String;
      Value : out Unbounded_String)
      return Boolean
   is
   begin
      if Index >= CLI.Argument_Count then
         TIO.Put_Line ("usage error: missing value for " & Name);
         return False;
      end if;

      Index := Index + 1;
      Value := To_Unbounded_String (CLI.Argument (Index));
      return True;
   end Need_Value;

begin
   declare
      I : Natural := 1;
   begin
      while I <= CLI.Argument_Count loop
         declare
            Arg   : constant String := CLI.Argument (I);
            Ok    : Boolean;
            Value : Unbounded_String;
         begin
            if Starts_With (Arg, "--input=") then
               Input_Path := To_Unbounded_String (Option_Value (Arg, "--input="));
               Have_Input := True;
            elsif Arg = "--input" then
               if not Need_Value (I, "--input", Value) then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
               Input_Path := Value;
               Have_Input := True;
            elsif Starts_With (Arg, "--wrapper=") then
               Config.Wrapper := Parse_Wrapper (Option_Value (Arg, "--wrapper="), Ok);
               if not Ok then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
            elsif Arg = "--wrapper" then
               if not Need_Value (I, "--wrapper", Value) then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
               Config.Wrapper := Parse_Wrapper (To_String (Value), Ok);
               if not Ok then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
            elsif Starts_With (Arg, "--input-chunk=") then
               Config.Input_Chunk := Parse_Positive (Option_Value (Arg, "--input-chunk="), Ok);
               if not Ok then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
            elsif Arg = "--input-chunk" then
               if not Need_Value (I, "--input-chunk", Value) then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
               Config.Input_Chunk := Parse_Positive (To_String (Value), Ok);
               if not Ok then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
            elsif Starts_With (Arg, "--output-chunk=") then
               Config.Output_Chunk := Parse_Positive (Option_Value (Arg, "--output-chunk="), Ok);
               if not Ok then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
            elsif Arg = "--output-chunk" then
               if not Need_Value (I, "--output-chunk", Value) then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
               Config.Output_Chunk := Parse_Positive (To_String (Value), Ok);
               if not Ok then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
            elsif Starts_With (Arg, "--repeat=") then
               Config.Repeat_Count := Parse_Positive (Option_Value (Arg, "--repeat="), Ok);
               if not Ok then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
            elsif Arg = "--repeat" then
               if not Need_Value (I, "--repeat", Value) then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
               Config.Repeat_Count := Parse_Positive (To_String (Value), Ok);
               if not Ok then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
            elsif Starts_With (Arg, "--expect-size=") then
               Config.Expect_Size := Parse_Natural (Option_Value (Arg, "--expect-size="), Ok);
               Config.Have_Expect := Ok;
               if not Ok then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
            elsif Arg = "--expect-size" then
               if not Need_Value (I, "--expect-size", Value) then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
               Config.Expect_Size := Parse_Natural (To_String (Value), Ok);
               Config.Have_Expect := Ok;
               if not Ok then
                  Usage;
                  CLI.Set_Exit_Status (CLI.Failure);
                  return;
               end if;
            elsif Arg = "--help" then
               Usage;
               return;
            else
               Usage;
               CLI.Set_Exit_Status (CLI.Failure);
               return;
            end if;

            I := I + 1;
         end;
      end loop;
   end;

   if not Have_Input then
      Usage;
      CLI.Set_Exit_Status (CLI.Failure);
      return;
   end if;

   declare
      Input           : constant Zlib.Byte_Array := Read_File (To_String (Input_Path), Status);
      Last_Output_Len : Natural := 0;
      Start_Time      : Ada.Calendar.Time;
      Stop_Time       : Ada.Calendar.Time;
      Total_Output    : Natural := 0;
   begin
      if Status /= Zlib.Ok then
         TIO.Put_Line ("input failed: " & Zlib.Status_Image (Status));
         CLI.Set_Exit_Status (CLI.Failure);
         return;
      end if;

      Start_Time := Ada.Calendar.Clock;
      for Iteration in 1 .. Config.Repeat_Count loop
         declare
            Decoded : constant Zlib.Byte_Array := Streaming_Inflate (Input, Config, Status);
         begin
            if Status /= Zlib.Ok then
               TIO.Put_Line ("inflate failed: " & Zlib.Status_Image (Status));
               CLI.Set_Exit_Status (CLI.Failure);
               return;
            end if;

            if Config.Have_Expect and then Decoded'Length /= Config.Expect_Size then
               TIO.Put_Line
                 ("expect-size failed: expected" & Natural'Image (Config.Expect_Size)
                  & ", got" & Natural'Image (Decoded'Length));
               CLI.Set_Exit_Status (CLI.Failure);
               return;
            end if;

            Last_Output_Len := Decoded'Length;
            Total_Output := Total_Output + Decoded'Length;
         end;
      end loop;
      Stop_Time := Ada.Calendar.Clock;

      TIO.Put_Line ("wrapper: " & Wrapper_Image (Config.Wrapper));
      TIO.Put_Line ("input bytes:" & Natural'Image (Input'Length));
      TIO.Put_Line ("output bytes:" & Natural'Image (Last_Output_Len));
      TIO.Put_Line ("compressed bytes:" & Natural'Image (Input'Length));
      TIO.Put_Line ("ratio:" & Long_Float'Image (Ratio (Input'Length, Last_Output_Len)) & "%");
      TIO.Put_Line ("repeat:" & Positive'Image (Config.Repeat_Count));
      TIO.Put_Line ("elapsed:" & Duration'Image (Stop_Time - Start_Time) & " s");
      TIO.Put_Line
        ("throughput:"
         & Long_Float'Image (Throughput_MiB_S (Total_Output, Stop_Time - Start_Time))
         & " MiB/s");
      TIO.Put_Line ("input chunk:" & Positive'Image (Config.Input_Chunk));
      TIO.Put_Line ("output chunk:" & Positive'Image (Config.Output_Chunk));
   end;
end Zlib_Bench_Inflate;
