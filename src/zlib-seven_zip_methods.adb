package body Zlib.Seven_Zip_Methods
  with SPARK_Mode => On
is

   function Descriptor
     (Method : Seven_Zip_Coder_Method) return Seven_Zip_Coder_Descriptor
   is
   begin
      case Method is
         when Seven_Zip_Copy =>
            return (ID_Length => 1, ID => [1 => 16#00#], others => <>);

         when Seven_Zip_Deflate_Method =>
            return
              (ID_Length => 3,
               ID        => [16#04#, 16#01#, 16#08#],
               others    => <>);

         when Seven_Zip_BZip2_Method =>
            return
              (ID_Length => 3,
               ID        => [16#04#, 16#02#, 16#02#],
               others    => <>);

         when Seven_Zip_LZMA_Method =>
            return
              (ID_Length => 3,
               ID        => [16#03#, 16#01#, 16#01#],
               others    => <>);

         when Seven_Zip_LZMA2_Method =>
            return (ID_Length => 1, ID => [1 => 16#21#], others => <>);

         when Seven_Zip_Delta_Method =>
            return (ID_Length => 1, ID => [1 => 16#03#], others => <>);

         when Seven_Zip_BCJ_X86_Method =>
            return
              (ID_Length => 4,
               ID        => [16#03#, 16#03#, 16#01#, 16#03#],
               others    => <>);

         when Seven_Zip_BCJ_ARM_Method =>
            return
              (ID_Length => 4,
               ID        => [16#03#, 16#03#, 16#05#, 16#01#],
               others    => <>);

         when Seven_Zip_BCJ_ARMT_Method =>
            return
              (ID_Length => 4,
               ID        => [16#03#, 16#03#, 16#07#, 16#01#],
               others    => <>);

         when Seven_Zip_BCJ_ARM64_Method =>
            return (ID_Length => 1, ID => [1 => 16#0A#], others => <>);

         when Seven_Zip_BCJ_PPC_Method =>
            return
              (ID_Length => 4,
               ID        => [16#03#, 16#03#, 16#02#, 16#05#],
               others    => <>);

         when Seven_Zip_BCJ_SPARC_Method =>
            return
              (ID_Length => 4,
               ID        => [16#03#, 16#03#, 16#08#, 16#05#],
               others    => <>);

         when Seven_Zip_BCJ_IA64_Method =>
            return
              (ID_Length => 4,
               ID        => [16#03#, 16#03#, 16#04#, 16#01#],
               others    => <>);

         when Seven_Zip_BCJ_RISCV_Method =>
            return (ID_Length => 1, ID => [1 => 16#0B#], others => <>);

         when Seven_Zip_BCJ2_Method =>
            return
              (ID_Length    => 4,
               ID           => [16#03#, 16#03#, 16#01#, 16#1B#],
               Input_Count  => 4,
               Output_Count => 1);

         when Seven_Zip_PPMd_Method =>
            return
              (ID_Length => 3,
               ID        => [16#03#, 16#04#, 16#01#],
               others    => <>);

         when Seven_Zip_AES_Method =>
            return
              (ID_Length => 4,
               ID        => [16#06#, 16#F1#, 16#07#, 16#01#],
               others    => <>);
      end case;
   end Descriptor;

   function Descriptor_Flags
     (Method         : Seven_Zip_Coder_Method;
      Has_Properties : Boolean) return Byte
   is
      Desc  : constant Seven_Zip_Coder_Descriptor := Descriptor (Method);
      Flags : Byte := Byte (Desc.ID_Length);
   begin
      if Desc.Input_Count /= 1 or else Desc.Output_Count /= 1 then
         Flags := Flags or 16#10#;
      end if;

      if Has_Properties then
         Flags := Flags or 16#20#;
      end if;

      return Flags;
   end Descriptor_Flags;

   function Method_Code_For_ID
     (ID        : Byte_Array;
      ID_Length : Natural) return Seven_Zip_Method_Code
   is
   begin
      if ID_Length = 1 then
         case ID (ID'First) is
            when 16#00# =>
               return 1;
            when 16#21# =>
               return 5;
            when 16#03# =>
               return 6;
            when 16#05# =>
               return 11;
            when 16#06# =>
               return 13;
            when 16#07# =>
               return 8;
            when 16#08# =>
               return 9;
            when 16#09# =>
               return 12;
            when 16#0A# =>
               return 10;
            when 16#0B# =>
               return 14;
            when others =>
               return Unknown_Method_Code;
         end case;
      elsif ID_Length = 3 then
         if ID (ID'First) = 16#04#
           and then ID (ID'First + 1) = 16#01#
           and then ID (ID'First + 2) = 16#08#
         then
            return 2;
         elsif ID (ID'First) = 16#04#
           and then ID (ID'First + 1) = 16#02#
           and then ID (ID'First + 2) = 16#02#
         then
            return 3;
         elsif ID (ID'First) = 16#03#
           and then ID (ID'First + 1) = 16#01#
           and then ID (ID'First + 2) = 16#01#
         then
            return 4;
         elsif ID (ID'First) = 16#03#
           and then ID (ID'First + 1) = 16#04#
           and then ID (ID'First + 2) = 16#01#
         then
            return 16;
         else
            return Unknown_Method_Code;
         end if;
      elsif ID_Length = 4 then
         if ID (ID'First) = 16#06#
           and then ID (ID'First + 1) = 16#F1#
           and then ID (ID'First + 2) = 16#07#
           and then ID (ID'First + 3) = 16#01#
         then
            return 17;
         elsif ID (ID'First) = 16#03#
           and then ID (ID'First + 1) = 16#03#
           and then ID (ID'First + 2) = 16#01#
           and then ID (ID'First + 3) = 16#03#
         then
            return 7;
         elsif ID (ID'First) = 16#03#
           and then ID (ID'First + 1) = 16#03#
           and then ID (ID'First + 2) = 16#01#
           and then ID (ID'First + 3) = 16#1B#
         then
            return 15;
         elsif ID (ID'First) = 16#03#
           and then ID (ID'First + 1) = 16#03#
         then
            if ID (ID'First + 2) = 16#05#
              and then ID (ID'First + 3) = 16#01#
            then
               return 8;
            elsif ID (ID'First + 2) = 16#07#
              and then ID (ID'First + 3) = 16#01#
            then
               return 9;
            elsif ID (ID'First + 2) = 16#02#
              and then ID (ID'First + 3) = 16#05#
            then
               return 11;
            elsif ID (ID'First + 2) = 16#08#
              and then ID (ID'First + 3) = 16#05#
            then
               return 12;
            elsif ID (ID'First + 2) = 16#04#
              and then ID (ID'First + 3) = 16#01#
            then
               return 13;
            else
               return Unknown_Method_Code;
            end if;
         else
            return Unknown_Method_Code;
         end if;
      end if;

      return Unknown_Method_Code;
   end Method_Code_For_ID;

   function Method_For_ID
     (ID        : Byte_Array;
      ID_Length : Natural;
      Method    : out Seven_Zip_Coder_Method) return Boolean
     with SPARK_Mode => Off
   is
   begin
      Method := Seven_Zip_Copy;

      case Method_Code_For_ID (ID, ID_Length) is
         when 1 =>
            Method := Seven_Zip_Copy;
         when 2 =>
            Method := Seven_Zip_Deflate_Method;
         when 3 =>
            Method := Seven_Zip_BZip2_Method;
         when 4 =>
            Method := Seven_Zip_LZMA_Method;
         when 5 =>
            Method := Seven_Zip_LZMA2_Method;
         when 6 =>
            Method := Seven_Zip_Delta_Method;
         when 7 =>
            Method := Seven_Zip_BCJ_X86_Method;
         when 8 =>
            Method := Seven_Zip_BCJ_ARM_Method;
         when 9 =>
            Method := Seven_Zip_BCJ_ARMT_Method;
         when 10 =>
            Method := Seven_Zip_BCJ_ARM64_Method;
         when 11 =>
            Method := Seven_Zip_BCJ_PPC_Method;
         when 12 =>
            Method := Seven_Zip_BCJ_SPARC_Method;
         when 13 =>
            Method := Seven_Zip_BCJ_IA64_Method;
         when 14 =>
            Method := Seven_Zip_BCJ_RISCV_Method;
         when 15 =>
            Method := Seven_Zip_BCJ2_Method;
         when 16 =>
            Method := Seven_Zip_PPMd_Method;
         when 17 =>
            Method := Seven_Zip_AES_Method;
         when Unknown_Method_Code =>
            return False;
      end case;

      return True;
   end Method_For_ID;

   function Method_For_Filter
     (Filter : Seven_Zip_Filter_Method) return Seven_Zip_Coder_Method
   is
   begin
      case Filter is
         when Seven_Zip_Filter_X86_BCJ =>
            return Seven_Zip_BCJ_X86_Method;
         when Seven_Zip_Filter_ARM_BCJ =>
            return Seven_Zip_BCJ_ARM_Method;
         when Seven_Zip_Filter_ARMT_BCJ =>
            return Seven_Zip_BCJ_ARMT_Method;
         when Seven_Zip_Filter_ARM64_BCJ =>
            return Seven_Zip_BCJ_ARM64_Method;
         when Seven_Zip_Filter_PPC_BCJ =>
            return Seven_Zip_BCJ_PPC_Method;
         when Seven_Zip_Filter_SPARC_BCJ =>
            return Seven_Zip_BCJ_SPARC_Method;
         when Seven_Zip_Filter_IA64_BCJ =>
            return Seven_Zip_BCJ_IA64_Method;
         when Seven_Zip_Filter_RISCV_BCJ =>
            return Seven_Zip_BCJ_RISCV_Method;
         when Seven_Zip_Filter_Delta =>
            return Seven_Zip_Delta_Method;
      end case;
   end Method_For_Filter;

   function Method_For_Codec
     (Codec : Seven_Zip_Codec_Method) return Seven_Zip_Coder_Method
   is
   begin
      case Codec is
         when Seven_Zip_Codec_Deflate =>
            return Seven_Zip_Deflate_Method;
         when Seven_Zip_Codec_BZip2 =>
            return Seven_Zip_BZip2_Method;
         when Seven_Zip_Codec_LZMA =>
            return Seven_Zip_LZMA_Method;
         when Seven_Zip_Codec_LZMA2 =>
            return Seven_Zip_LZMA2_Method;
         when Seven_Zip_Codec_PPMd =>
            return Seven_Zip_PPMd_Method;
      end case;
   end Method_For_Codec;

   function Method_For_Graph
     (Method : Seven_Zip_Graph_Method) return Seven_Zip_Coder_Method
   is
   begin
      case Method is
         when Seven_Zip_Graph_Copy =>
            return Seven_Zip_Copy;
         when Seven_Zip_Graph_Deflate =>
            return Seven_Zip_Deflate_Method;
         when Seven_Zip_Graph_BZip2 =>
            return Seven_Zip_BZip2_Method;
         when Seven_Zip_Graph_LZMA =>
            return Seven_Zip_LZMA_Method;
         when Seven_Zip_Graph_LZMA2 =>
            return Seven_Zip_LZMA2_Method;
         when Seven_Zip_Graph_PPMd =>
            return Seven_Zip_PPMd_Method;
         when Seven_Zip_Graph_Delta =>
            return Seven_Zip_Delta_Method;
         when Seven_Zip_Graph_X86_BCJ =>
            return Seven_Zip_BCJ_X86_Method;
         when Seven_Zip_Graph_ARM_BCJ =>
            return Seven_Zip_BCJ_ARM_Method;
         when Seven_Zip_Graph_ARMT_BCJ =>
            return Seven_Zip_BCJ_ARMT_Method;
         when Seven_Zip_Graph_ARM64_BCJ =>
            return Seven_Zip_BCJ_ARM64_Method;
         when Seven_Zip_Graph_PPC_BCJ =>
            return Seven_Zip_BCJ_PPC_Method;
         when Seven_Zip_Graph_SPARC_BCJ =>
            return Seven_Zip_BCJ_SPARC_Method;
         when Seven_Zip_Graph_IA64_BCJ =>
            return Seven_Zip_BCJ_IA64_Method;
         when Seven_Zip_Graph_RISCV_BCJ =>
            return Seven_Zip_BCJ_RISCV_Method;
         when Seven_Zip_Graph_BCJ2 =>
            return Seven_Zip_BCJ2_Method;
      end case;
   end Method_For_Graph;

   function Is_Propertyless_Coder
     (Method : Seven_Zip_Coder_Method) return Boolean is
   begin
      return Method in Seven_Zip_Copy
                       | Seven_Zip_Deflate_Method
                       | Seven_Zip_BZip2_Method
                       | Seven_Zip_BCJ_X86_Method
                       | Seven_Zip_BCJ_ARM_Method
                       | Seven_Zip_BCJ_ARMT_Method
                       | Seven_Zip_BCJ_ARM64_Method
                       | Seven_Zip_BCJ_PPC_Method
                       | Seven_Zip_BCJ_SPARC_Method
                       | Seven_Zip_BCJ_IA64_Method
                       | Seven_Zip_BCJ_RISCV_Method;
   end Is_Propertyless_Coder;

   function Is_Branch_Converter
     (Method : Seven_Zip_Coder_Method) return Boolean is
   begin
      return Method in Seven_Zip_BCJ_ARM_Method
                       | Seven_Zip_BCJ_ARMT_Method
                       | Seven_Zip_BCJ_ARM64_Method
                       | Seven_Zip_BCJ_PPC_Method
                       | Seven_Zip_BCJ_SPARC_Method
                       | Seven_Zip_BCJ_IA64_Method
                       | Seven_Zip_BCJ_RISCV_Method;
   end Is_Branch_Converter;

   function Is_BCJ2_Main_Chain_Coder
     (Method : Seven_Zip_Coder_Method) return Boolean is
   begin
      return Method in Seven_Zip_Copy
                       | Seven_Zip_Deflate_Method
                       | Seven_Zip_BZip2_Method
                       | Seven_Zip_LZMA_Method
                       | Seven_Zip_LZMA2_Method
                       | Seven_Zip_Delta_Method
                       | Seven_Zip_BCJ_X86_Method
                       | Seven_Zip_BCJ_ARM_Method
                       | Seven_Zip_BCJ_ARMT_Method
                       | Seven_Zip_BCJ_PPC_Method
                       | Seven_Zip_BCJ_SPARC_Method
                       | Seven_Zip_BCJ_ARM64_Method
                       | Seven_Zip_BCJ_IA64_Method
                       | Seven_Zip_BCJ_RISCV_Method
                       | Seven_Zip_PPMd_Method;
   end Is_BCJ2_Main_Chain_Coder;

   function Branch_Arch_Of
     (Method : Seven_Zip_Coder_Method)
      return Zlib.Seven_Zip_Filters.Branch_Arch
   is
   begin
      case Method is
         when Seven_Zip_BCJ_ARM_Method =>
            return Zlib.Seven_Zip_Filters.ARM;
         when Seven_Zip_BCJ_ARMT_Method =>
            return Zlib.Seven_Zip_Filters.ARMT;
         when Seven_Zip_BCJ_ARM64_Method =>
            return Zlib.Seven_Zip_Filters.ARM64;
         when Seven_Zip_BCJ_PPC_Method =>
            return Zlib.Seven_Zip_Filters.PPC;
         when Seven_Zip_BCJ_SPARC_Method =>
            return Zlib.Seven_Zip_Filters.SPARC;
         when Seven_Zip_BCJ_IA64_Method =>
            return Zlib.Seven_Zip_Filters.IA64;
         when Seven_Zip_BCJ_RISCV_Method =>
            return Zlib.Seven_Zip_Filters.RISCV;
         when others =>
            raise Program_Error;
      end case;
   end Branch_Arch_Of;

end Zlib.Seven_Zip_Methods;
