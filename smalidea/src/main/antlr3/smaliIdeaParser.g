/*
 * Copyright 2012, Google Inc.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 *     * Redistributions of source code must retain the above copyright
 * notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above
 * copyright notice, this list of conditions and the following disclaimer
 * in the documentation and/or other materials provided with the
 * distribution.
 *     * Neither the name of Google Inc. nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

parser grammar smaliIdeaParser;

options {
  tokenVocab=smaliParser;
}

@header {
package org.jf.smalidea;

import org.jf.smalidea.psi.ElementTypes;
import com.intellij.lang.PsiBuilder;
import static com.intellij.lang.PsiBuilder.Marker;
}


@members {
  private PsiBuilder psiBuilder;

  public void setPsiBuilder(PsiBuilder psiBuilder) {
      this.psiBuilder = psiBuilder;
  }

  public Marker mark() {
      return psiBuilder.mark();
  }

    protected void syncToFollows(boolean acceptEof)
    {
        BitSet follow = computeErrorRecoverySet();
        int mark = input.mark();
        Marker marker = null;
        try {
            int token = input.LA(1);
            while (!follow.member(token)) {
                if (token == Token.EOF) {
                    if (acceptEof) {
                        break;
                    }
                    input.rewind();
                    mark = -1;
                    marker = null;
                    return;
                }
                if (marker == null) {
                    marker = mark();
                }
                input.consume();
                token = input.LA(1);
            }
        } finally {
            if  (mark != -1) {
                input.release(mark);
            }
            if (marker != null) {
                marker.error("Unexpected tokens");
            }
        }
    }

    @Override
    public void recover(IntStream input, RecognitionException re) {
        Marker mark = mark();
        super.recover(input, re);
        mark.error(getErrorMessage(re, tokenNames));
    }

    @Override
    protected Object recoverFromMismatchedToken(IntStream input, int ttype, BitSet follow)
            throws RecognitionException
    {
        RecognitionException e = null;
        // if next token is what we are looking for then "delete" this token
        if ( mismatchIsUnwantedToken(input, ttype) ) {
            e = new UnwantedTokenException(ttype, input);
            /*
               System.err.println("recoverFromMismatchedToken deleting "+
                                  ((TokenStream)input).LT(1)+
                                  " since "+((TokenStream)input).LT(2)+" is what we want");
                */
            beginResync();
            Marker mark = mark();
            input.consume(); // simply delete extra token
            mark.error(getErrorMessage(e, tokenNames));
            endResync();
            reportError(e);  // report after consuming so AW sees the token in the exception
            // we want to return the token we're actually matching
            Object matchedSymbol = getCurrentInputSymbol(input);
            input.consume(); // move past ttype token as if all were ok
            return matchedSymbol;
        }
        // can't recover with single token deletion, try insertion
        if ( mismatchIsMissingToken(input, follow) ) {
            Object inserted = getMissingSymbol(input, e, ttype, follow);
            e = new MissingTokenException(ttype, input, inserted);
            reportError(e);  // report after inserting so AW sees the token in the exception
            return inserted;
        }
        // even that didn't work; must throw the exception
        e = new MismatchedTokenException(ttype, input);
        throw e;
    }
}

sync[boolean toEof]
  @init { syncToFollows($toEof); }
  : /*epsilon*/;


smali_file
  @init {
    mark().done(ElementTypes.MODIFIER_LIST);
    mark().done(ElementTypes.EXTENDS_LIST);
    mark().done(ElementTypes.IMPLEMENTS_LIST);
  }
  : (class_element sync[true])+ EOF;

class_element
  :
  ( class_spec
  | super_spec
  | implements_spec
  | source_spec
  | method
  | field
  | annotation);

class_spec
  @init { Marker marker = mark(); }
  : CLASS_DIRECTIVE access_list class_descriptor;
  finally { marker.done(ElementTypes.CLASS_SPEC); }

super_spec
  @init { Marker marker = mark(); }
  : SUPER_DIRECTIVE class_descriptor;
  finally { marker.done(ElementTypes.SUPER_SPEC); }

implements_spec
  @init { Marker marker = mark(); }
  : IMPLEMENTS_DIRECTIVE class_descriptor;
  finally { marker.done(ElementTypes.IMPLEMENTS_SPEC); }

source_spec
  @init { Marker marker = mark(); }
  : SOURCE_DIRECTIVE STRING_LITERAL;
  finally { marker.done(ElementTypes.SOURCE_SPEC); }

access_list
  @init { Marker marker = mark(); }
  : ACCESS_SPEC*;
  finally { marker.done(ElementTypes.ACCESS_LIST); }


/*When there are annotations immediately after a field definition, we don't know whether they are field annotations
or class annotations until we determine if there is an .end field directive. In either case, we still "consume" and parse
the annotations. If it turns out that they are field annotations, we include them in the I_FIELD AST. Otherwise, we
add them to the $smali_file::classAnnotations list*/
field
  @init {
    Marker marker = mark();
    Marker annotationsMarker = null;
    boolean classAnnotations = true;
  }
  : FIELD_DIRECTIVE access_list member_name COLON nonvoid_type_descriptor (EQUAL literal)?
    ( END_FIELD_DIRECTIVE
    | (ANNOTATION_DIRECTIVE)=> ( {annotationsMarker = mark();}
                                 ((ANNOTATION_DIRECTIVE)=> annotation)+
                                 (END_FIELD_DIRECTIVE {classAnnotations = false;})?
                               )
    | /*epsilon*/
    );
  finally {
    if (annotationsMarker != null) {
      if (classAnnotations) {
        marker.doneBefore(ElementTypes.FIELD, annotationsMarker);
        annotationsMarker.drop();
      } else {
        annotationsMarker.drop();
        marker.done(ElementTypes.FIELD);
      }
    } else {
      marker.done(ElementTypes.FIELD);
    }
  }

method
  @init { Marker marker = mark(); }
  : METHOD_DIRECTIVE access_list member_name method_prototype statements_and_directives END_METHOD_DIRECTIVE;
  finally { marker.done(ElementTypes.METHOD); }

statements_and_directives
  : (
      ( ordered_method_item
      | registers_directive
      | catch_directive
      | catchall_directive
      | parameter_directive
      | annotation
      )
    sync[false])*;

/* Method items whose order/location is important */
ordered_method_item
  : label
  | instruction
  | debug_directive;

registers_directive
  @init { Marker marker = mark(); }
  : ( REGISTERS_DIRECTIVE integral_literal
    | LOCALS_DIRECTIVE integral_literal
    );
  finally { marker.done(ElementTypes.REGISTERS_SPEC); }

/*identifiers are much more general than most languages. Any of the below can either be
the indicated type OR an identifier, depending on the context*/
simple_name
  @init { Marker marker = mark(); }
  @after { marker.done(ElementTypes.SIMPLE_NAME); }
  : SIMPLE_NAME
  | ACCESS_SPEC
  | VERIFICATION_ERROR_TYPE
  | POSITIVE_INTEGER_LITERAL
  | NEGATIVE_INTEGER_LITERAL
  | FLOAT_LITERAL_OR_ID
  | DOUBLE_LITERAL_OR_ID
  | BOOL_LITERAL
  | NULL_LITERAL
  | REGISTER
  | PARAM_LIST_OR_ID
  | PRIMITIVE_TYPE
  | VOID_TYPE
  | ANNOTATION_VISIBILITY
  | INSTRUCTION_FORMAT10t
  | INSTRUCTION_FORMAT10x
  | INSTRUCTION_FORMAT10x_ODEX
  | INSTRUCTION_FORMAT11x
  | INSTRUCTION_FORMAT12x_OR_ID
  | INSTRUCTION_FORMAT21c_FIELD
  | INSTRUCTION_FORMAT21c_FIELD_ODEX
  | INSTRUCTION_FORMAT21c_STRING
  | INSTRUCTION_FORMAT21c_TYPE
  | INSTRUCTION_FORMAT21t
  | INSTRUCTION_FORMAT22c_FIELD
  | INSTRUCTION_FORMAT22c_FIELD_ODEX
  | INSTRUCTION_FORMAT22c_TYPE
  | INSTRUCTION_FORMAT22cs_FIELD
  | INSTRUCTION_FORMAT22s_OR_ID
  | INSTRUCTION_FORMAT22t
  | INSTRUCTION_FORMAT23x
  | INSTRUCTION_FORMAT31i_OR_ID
  | INSTRUCTION_FORMAT31t
  | INSTRUCTION_FORMAT35c_METHOD
  | INSTRUCTION_FORMAT35c_METHOD_ODEX
  | INSTRUCTION_FORMAT35c_TYPE
  | INSTRUCTION_FORMAT35mi_METHOD
  | INSTRUCTION_FORMAT35ms_METHOD
  | INSTRUCTION_FORMAT51l;
  catch [RecognitionException ex] { marker.error(getErrorMessage(ex, tokenNames)); recover(input,ex); }

member_name
  @init { Marker marker = mark(); }
  : simple_name
  | MEMBER_NAME;
  finally { marker.done(ElementTypes.MEMBER_NAME); }

method_prototype
  @init { Marker marker = mark(); }
  : OPEN_PAREN param_list CLOSE_PAREN type_descriptor;
  finally { marker.done(ElementTypes.METHOD_PROTOTYPE); }

param_list
  @init { Marker marker = mark(); }
  : PARAM_LIST
  | PARAM_LIST_OR_ID
  | nonvoid_type_descriptor*;
  finally { marker.done(ElementTypes.METHOD_PARAM_LIST); }

void_type
  @init { Marker marker = mark(); }
  : VOID_TYPE;
  finally { marker.done(ElementTypes.VOID_TYPE); }

primitive_type
  @init { Marker marker = mark(); }
  : PRIMITIVE_TYPE;
  finally { marker.done(ElementTypes.PRIMITIVE_TYPE); }

class_descriptor
  @init { Marker marker = mark(); }
  : CLASS_DESCRIPTOR;
  finally { marker.done(ElementTypes.CLASS_TYPE); }

type_descriptor
  : void_type
  | primitive_type
  | class_descriptor
  | ARRAY_DESCRIPTOR;

nonvoid_type_descriptor
  : primitive_type
  | class_descriptor
  | ARRAY_DESCRIPTOR;

reference_type_descriptor
  : class_descriptor
  | ARRAY_DESCRIPTOR;

integer_literal
  : POSITIVE_INTEGER_LITERAL
  | NEGATIVE_INTEGER_LITERAL;

float_literal
  : FLOAT_LITERAL_OR_ID
  | FLOAT_LITERAL;

double_literal
  : DOUBLE_LITERAL_OR_ID
  | DOUBLE_LITERAL;

literal
  @init { Marker marker = mark(); }
  : LONG_LITERAL
  | integer_literal
  | SHORT_LITERAL
  | BYTE_LITERAL
  | float_literal
  | double_literal
  | CHAR_LITERAL
  | STRING_LITERAL
  | BOOL_LITERAL
  | NULL_LITERAL
  | array_literal
  | subannotation
  | type_field_method_literal
  | enum_literal;
  finally { marker.done(ElementTypes.LITERAL); }

integral_literal
  @init { Marker marker = mark(); }
  : LONG_LITERAL
  | integer_literal
  | SHORT_LITERAL
  | CHAR_LITERAL
  | BYTE_LITERAL;
  finally { marker.done(ElementTypes.LITERAL); }

fixed_32bit_literal
  : LONG_LITERAL
  | integer_literal
  | SHORT_LITERAL
  | BYTE_LITERAL
  | float_literal
  | CHAR_LITERAL
  | BOOL_LITERAL;

fixed_literal
  : integer_literal
  | LONG_LITERAL
  | SHORT_LITERAL
  | BYTE_LITERAL
  | float_literal
  | double_literal
  | CHAR_LITERAL
  | BOOL_LITERAL;

array_literal
  : OPEN_BRACE (literal (COMMA literal)* | ) CLOSE_BRACE;

annotation_element
  : simple_name EQUAL literal;


annotation
  @init { Marker marker = mark(); }
  : ANNOTATION_DIRECTIVE ANNOTATION_VISIBILITY class_descriptor
    annotation_element* END_ANNOTATION_DIRECTIVE;
  finally { marker.done(ElementTypes.ANNOTATION); }

subannotation
  : SUBANNOTATION_DIRECTIVE class_descriptor annotation_element* END_SUBANNOTATION_DIRECTIVE;

enum_literal
  : ENUM_DIRECTIVE reference_type_descriptor ARROW simple_name COLON reference_type_descriptor;

type_field_method_literal
  : reference_type_descriptor
    ( ARROW
      ( member_name COLON nonvoid_type_descriptor
      | member_name method_prototype
      )
    |   /*epsilon*/
    )
  | primitive_type
  | void_type;

fully_qualified_method
  : reference_type_descriptor ARROW member_name method_prototype;

fully_qualified_field
  : reference_type_descriptor ARROW member_name COLON nonvoid_type_descriptor;

label
  : COLON simple_name;

label_ref
  : COLON simple_name
  | NEGATIVE_INTEGER_LITERAL;

register_list
  : (REGISTER (COMMA REGISTER)*)?;

register_range
  : (REGISTER (DOTDOT REGISTER)?)?;

verification_error_reference
  : class_descriptor | fully_qualified_field | fully_qualified_method;

catch_directive
  : CATCH_DIRECTIVE nonvoid_type_descriptor OPEN_BRACE label_ref DOTDOT label_ref CLOSE_BRACE label_ref;

catchall_directive
  : CATCHALL_DIRECTIVE OPEN_BRACE label_ref DOTDOT label_ref CLOSE_BRACE label_ref;

/*When there are annotations immediately after a parameter definition, we don't know whether they are parameter annotations
or method annotations until we determine if there is an .end parameter directive. In either case, we still "consume" and parse
the annotations. If it turns out that they are parameter annotations, we include them in the I_PARAMETER AST. Otherwise, we
add them to the $statements_and_directives::methodAnnotations list*/
parameter_directive
  : PARAMETER_DIRECTIVE REGISTER (COMMA STRING_LITERAL)?
    ({input.LA(1) == ANNOTATION_DIRECTIVE}? annotation)*
    ( END_PARAMETER_DIRECTIVE
    | /*epsilon*/
    );

debug_directive
  : line_directive
  | local_directive
  | end_local_directive
  | restart_local_directive
  | prologue_directive
  | epilogue_directive
  | source_directive;

line_directive
  : LINE_DIRECTIVE integral_literal;

local_directive
  : LOCAL_DIRECTIVE REGISTER (COMMA (NULL_LITERAL | STRING_LITERAL) COLON (VOID_TYPE | nonvoid_type_descriptor)
                              (COMMA STRING_LITERAL)? )?;

end_local_directive
  : END_LOCAL_DIRECTIVE REGISTER;

restart_local_directive
  : RESTART_LOCAL_DIRECTIVE REGISTER;

prologue_directive
  : PROLOGUE_DIRECTIVE;

epilogue_directive
  : EPILOGUE_DIRECTIVE;

source_directive
  : SOURCE_DIRECTIVE STRING_LITERAL?;

instruction_format12x
  : INSTRUCTION_FORMAT12x
  | INSTRUCTION_FORMAT12x_OR_ID;

instruction_format22s
  : INSTRUCTION_FORMAT22s
  | INSTRUCTION_FORMAT22s_OR_ID;

instruction_format31i
  : INSTRUCTION_FORMAT31i
  | INSTRUCTION_FORMAT31i_OR_ID;

instruction
  @init { Marker marker = mark(); }
  : insn_format10t
  | insn_format10x
  | insn_format10x_odex
  | insn_format11n
  | insn_format11x
  | insn_format12x
  | insn_format20bc
  | insn_format20t
  | insn_format21c_field
  | insn_format21c_field_odex
  | insn_format21c_string
  | insn_format21c_type
  | insn_format21ih
  | insn_format21lh
  | insn_format21s
  | insn_format21t
  | insn_format22b
  | insn_format22c_field
  | insn_format22c_field_odex
  | insn_format22c_type
  | insn_format22cs_field
  | insn_format22s
  | insn_format22t
  | insn_format22x
  | insn_format23x
  | insn_format30t
  | insn_format31c
  | insn_format31i
  | insn_format31t
  | insn_format32x
  | insn_format35c_method
  | insn_format35c_type
  | insn_format35c_method_odex
  | insn_format35mi_method
  | insn_format35ms_method
  | insn_format3rc_method
  | insn_format3rc_method_odex
  | insn_format3rc_type
  | insn_format3rmi_method
  | insn_format3rms_method
  | insn_format51l
  | insn_array_data_directive
  | insn_packed_switch_directive
  | insn_sparse_switch_directive;
  finally { marker.done(ElementTypes.INSTRUCTION); }

insn_format10t returns [int size]
  : //e.g. goto endloop:
    //e.g. goto +3
    INSTRUCTION_FORMAT10t label_ref;

insn_format10x returns [int size]
  : //e.g. return-void
    INSTRUCTION_FORMAT10x;

insn_format10x_odex returns [int size]
  : //e.g. return-void-barrier
    INSTRUCTION_FORMAT10x_ODEX;

insn_format11n returns [int size]
  : //e.g. const/4 v0, 5
    INSTRUCTION_FORMAT11n REGISTER COMMA integral_literal;

insn_format11x returns [int size]
  : //e.g. move-result-object v1
    INSTRUCTION_FORMAT11x REGISTER;

insn_format12x returns [int size]
  : //e.g. move v1 v2
    instruction_format12x REGISTER COMMA REGISTER;

insn_format20bc returns [int size]
  : //e.g. throw-verification-error generic-error, Lsome/class;
    INSTRUCTION_FORMAT20bc VERIFICATION_ERROR_TYPE COMMA verification_error_reference;

insn_format20t returns [int size]
  : //e.g. goto/16 endloop:
    INSTRUCTION_FORMAT20t label_ref;

insn_format21c_field returns [int size]
  : //e.g. sget-object v0, java/lang/System/out LJava/io/PrintStream;
    INSTRUCTION_FORMAT21c_FIELD REGISTER COMMA fully_qualified_field;

insn_format21c_field_odex returns [int size]
  : //e.g. sget-object-volatile v0, java/lang/System/out LJava/io/PrintStream;
    INSTRUCTION_FORMAT21c_FIELD_ODEX REGISTER COMMA fully_qualified_field;

insn_format21c_string returns [int size]
  : //e.g. const-string v1, "Hello World!"
    INSTRUCTION_FORMAT21c_STRING REGISTER COMMA STRING_LITERAL;

insn_format21c_type returns [int size]
  : //e.g. const-class v2, Lorg/jf/HelloWorld2/HelloWorld2;
    INSTRUCTION_FORMAT21c_TYPE REGISTER COMMA nonvoid_type_descriptor;

insn_format21ih returns [int size]
  : //e.g. const/high16 v1, 1234
    INSTRUCTION_FORMAT21ih REGISTER COMMA fixed_32bit_literal;

insn_format21lh returns [int size]
  : //e.g. const-wide/high16 v1, 1234
    INSTRUCTION_FORMAT21lh REGISTER COMMA fixed_32bit_literal;

insn_format21s returns [int size]
  : //e.g. const/16 v1, 1234
    INSTRUCTION_FORMAT21s REGISTER COMMA integral_literal;

insn_format21t returns [int size]
  : //e.g. if-eqz v0, endloop:
    INSTRUCTION_FORMAT21t REGISTER COMMA (label_ref);

insn_format22b returns [int size]
  : //e.g. add-int v0, v1, 123
    INSTRUCTION_FORMAT22b REGISTER COMMA REGISTER COMMA integral_literal;

insn_format22c_field returns [int size]
  : //e.g. iput-object v1, v0 org/jf/HelloWorld2/HelloWorld2.helloWorld Ljava/lang/String;
    INSTRUCTION_FORMAT22c_FIELD REGISTER COMMA REGISTER COMMA fully_qualified_field;

insn_format22c_field_odex returns [int size]
  : //e.g. iput-object-volatile v1, v0 org/jf/HelloWorld2/HelloWorld2.helloWorld Ljava/lang/String;
    INSTRUCTION_FORMAT22c_FIELD_ODEX REGISTER COMMA REGISTER COMMA fully_qualified_field;

insn_format22c_type returns [int size]
  : //e.g. instance-of v0, v1, Ljava/lang/String;
    INSTRUCTION_FORMAT22c_TYPE REGISTER COMMA REGISTER COMMA nonvoid_type_descriptor;

insn_format22cs_field returns [int size]
  : //e.g. iget-quick v0, v1, field@0xc
    INSTRUCTION_FORMAT22cs_FIELD REGISTER COMMA REGISTER COMMA FIELD_OFFSET;

insn_format22s returns [int size]
  : //e.g. add-int/lit16 v0, v1, 12345
    instruction_format22s REGISTER COMMA REGISTER COMMA integral_literal;

insn_format22t returns [int size]
  : //e.g. if-eq v0, v1, endloop:
    INSTRUCTION_FORMAT22t REGISTER COMMA REGISTER COMMA label_ref;

insn_format22x returns [int size]
  : //e.g. move/from16 v1, v1234
    INSTRUCTION_FORMAT22x REGISTER COMMA REGISTER;

insn_format23x returns [int size]
  : //e.g. add-int v1, v2, v3
    INSTRUCTION_FORMAT23x REGISTER COMMA REGISTER COMMA REGISTER;

insn_format30t returns [int size]
  : //e.g. goto/32 endloop:
    INSTRUCTION_FORMAT30t label_ref;

insn_format31c returns [int size]
  : //e.g. const-string/jumbo v1 "Hello World!"
    INSTRUCTION_FORMAT31c REGISTER COMMA STRING_LITERAL;

insn_format31i returns [int size]
  : //e.g. const v0, 123456
    instruction_format31i REGISTER COMMA fixed_32bit_literal;

insn_format31t returns [int size]
  : //e.g. fill-array-data v0, ArrayData:
    INSTRUCTION_FORMAT31t REGISTER COMMA label_ref;

insn_format32x returns [int size]
  : //e.g. move/16 v4567, v1234
    INSTRUCTION_FORMAT32x REGISTER COMMA REGISTER;

insn_format35c_method returns [int size]
  : //e.g. invoke-virtual {v0,v1} java/io/PrintStream/print(Ljava/lang/Stream;)V
    INSTRUCTION_FORMAT35c_METHOD OPEN_BRACE register_list CLOSE_BRACE COMMA fully_qualified_method;

insn_format35c_type returns [int size]
  : //e.g. filled-new-array {v0,v1}, I
    INSTRUCTION_FORMAT35c_TYPE OPEN_BRACE register_list CLOSE_BRACE COMMA nonvoid_type_descriptor;

insn_format35c_method_odex returns [int size]
  : //e.g. invoke-direct {p0}, Ljava/lang/Object;-><init>()V
    INSTRUCTION_FORMAT35c_METHOD_ODEX OPEN_BRACE register_list CLOSE_BRACE COMMA fully_qualified_method;

insn_format35mi_method returns [int size]
  : //e.g. execute-inline {v0, v1}, inline@0x4
    INSTRUCTION_FORMAT35mi_METHOD OPEN_BRACE register_list CLOSE_BRACE COMMA INLINE_INDEX;

insn_format35ms_method returns [int size]
  : //e.g. invoke-virtual-quick {v0, v1}, vtable@0x4
    INSTRUCTION_FORMAT35ms_METHOD OPEN_BRACE register_list CLOSE_BRACE COMMA VTABLE_INDEX;

insn_format3rc_method returns [int size]
  : //e.g. invoke-virtual/range {v25..v26}, java/lang/StringBuilder/append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    INSTRUCTION_FORMAT3rc_METHOD OPEN_BRACE register_range CLOSE_BRACE COMMA fully_qualified_method;

insn_format3rc_method_odex returns [int size]
  : //e.g. invoke-object-init/range {p0}, Ljava/lang/Object;-><init>()V
    INSTRUCTION_FORMAT3rc_METHOD_ODEX OPEN_BRACE register_list CLOSE_BRACE COMMA fully_qualified_method;

insn_format3rc_type returns [int size]
  : //e.g. filled-new-array/range {v0..v6}, I
    INSTRUCTION_FORMAT3rc_TYPE OPEN_BRACE register_range CLOSE_BRACE COMMA nonvoid_type_descriptor;

insn_format3rmi_method returns [int size]
  : //e.g. execute-inline/range {v0 .. v10}, inline@0x14
    INSTRUCTION_FORMAT3rmi_METHOD OPEN_BRACE register_range CLOSE_BRACE COMMA INLINE_INDEX;

insn_format3rms_method returns [int size]
  : //e.g. invoke-virtual-quick/range {v0 .. v10}, vtable@0x14
    INSTRUCTION_FORMAT3rms_METHOD OPEN_BRACE register_range CLOSE_BRACE COMMA VTABLE_INDEX;

insn_format51l returns [int size]
  : //e.g. const-wide v0, 5000000000L
    INSTRUCTION_FORMAT51l REGISTER COMMA fixed_literal;

insn_array_data_directive returns [int size]
  : ARRAY_DATA_DIRECTIVE integral_literal fixed_literal* END_ARRAY_DATA_DIRECTIVE;

insn_packed_switch_directive returns [int size]
  : PACKED_SWITCH_DIRECTIVE fixed_32bit_literal label_ref* END_PACKED_SWITCH_DIRECTIVE;

insn_sparse_switch_directive returns [int size]
  : SPARSE_SWITCH_DIRECTIVE (fixed_32bit_literal ARROW label_ref)* END_SPARSE_SWITCH_DIRECTIVE;