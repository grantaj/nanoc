/*
 * From ORIGINAL nanoc1 expression/statement nodes to the small 6502
 * traversal operation tape. No source parsing, function-name matching,
 * instruction search or peephole rewriting occurs here.
 *
 * This is intentionally a STRICT subset: unsupported semantics cause
 * rejection rather than guessing. It preserves the original parser's
 * type/syntax decisions, and chooses physical index/pointer homes once.
 *
 * Included by the host-only parser_tape_driver after parser_tape.c and
 * traversal_backend.c. Production compiler integration is still in progress.
 */

char nd_error;
unsigned nd_failure_event;
char nd_map_count;
char nd_map_area[64];
char nd_map_symbol[64];
char nd_map_kind[64];     /* 1 scalar, 2 array, 3 pointer, 4 scaled base */
char nd_map_id[64];
unsigned nd_map_event[64];/* tape event constructing a scaled base */
char nd_next_scalar;
char nd_next_array;
char nd_next_pointer;
char nd_var_area[32];
char nd_var_symbol[32];
char nd_ptr_area[2];
char nd_ptr_symbol[2];
char nd_array_symbol[32];
char nd_wide_index_used;  /* wide array cursor currently owns __tptr00 */

/* Temporary path for a left-associated numeric expression chain. Reuse the
 * same two accumulator bytes for every expression of a function: no AST
 * recursion, evaluation stack, or heap allocation. */
unsigned nd_chain_right[32];
char nd_chain_sign[32];

char *nd_source_name(char area, char symbol)
{
    if (area == 1) return global_name + symbol * 32;
    return local_name + symbol * 32;
}

int nd_find(char area, char symbol)
{
    unsigned i;
    i=0;
    while (i<nd_map_count) {
        if (nd_map_area[i]==area & nd_map_symbol[i]==symbol) return i;
        i=i+1;
    }
    return -1;
}

int nd_record(char area, char symbol, char kind)
{
    int i;
    char id;
    i=nd_find(area,symbol);
    if (i>=0) {
        if (nd_map_kind[i]!=kind) { nd_error=1; return -1; }
        return nd_map_id[i];
    }
    if (nd_map_count>=64) { nd_error=2; return -1; }
    if (kind==1) {
        if (nd_next_scalar>=32) { nd_error=3; return -1; }
        id=nd_next_scalar;
        nd_next_scalar=id+1;
        nd_var_area[id]=area;
        nd_var_symbol[id]=symbol;
    } else if (kind==2) {
        if (nd_next_array>=32) { nd_error=3; return -1; }
        id=nd_next_array;
        nd_next_array=id+1;
        nd_array_symbol[id]=symbol;
    } else if (kind==3 | kind==4) {
        if (nd_next_pointer>=2) { nd_error=4; return -1; }
        id=nd_next_pointer;
        nd_next_pointer=id+1;
        nd_ptr_area[id]=area;
        nd_ptr_symbol[id]=symbol;
    } else { nd_error=5; return -1; }
    nd_map_area[nd_map_count]=area;
    nd_map_symbol[nd_map_count]=symbol;
    nd_map_kind[nd_map_count]=kind;
    nd_map_id[nd_map_count]=id;
    nd_map_event[nd_map_count]=65535;
    nd_map_count=nd_map_count+1;
    return id;
}

int nd_scalar(unsigned node)
{
    if (node==0 | nc2_kind[node]!=2) { nd_error=6; return -1; }
    /* Only an actual byte may inhabit an 8-bit scalar home.
     * Int/unsigned and pointers require separate complete lowering.
     */
    if (nc2_number[node]!=1) { nd_error=7; return -1; }
    return nd_record(nc2_a[node],nc2_b[node],1);
}

/* Word scalars keep the same static Nano C two-byte homes, but are
 * never assigned X/Y traversal identities. The target emitter handles
 * their low and high bytes explicitly, without generic register planning.
 */
int nd_word(unsigned node)
{
    if(node==0 | nc2_kind[node]!=2) {nd_error=30;return -1;}
    if(nc2_number[node]!=2 & nc2_number[node]!=3) {
        nd_error=30;return -1;
    }
    return nd_record(nc2_a[node],nc2_b[node],1);
}

int nd_array(char area, char symbol)
{
    if (area!=1 | global_kind[symbol]!=2 | global_type[symbol]!=1) {
        nd_error=8; return -1;
    }
    return nd_record(area,symbol,2);
}

int nd_pointer(char area, char symbol)
{
    return nd_record(area,symbol,3);
}

int nd_base(char area, char symbol)
{
    int i;
    i=nd_find(area,symbol);
    if (i<0 | nd_map_kind[i]!=4) { nd_error=9; return -1; }
    return i;
}

char nd_add(char op, char dst, char a, char b, unsigned number)
{
    if (tb_add(op,dst,a,b,number)==0) {
        nd_error=10; return 0;
    }
    return 1;
}

/* Wide source index for a byte array. A 16-bit scalar or a simple
 * scalar +/- literal is an address displacement, not an 8-bit X/Y index.
 * For a byte array the emitted load returns A exactly as direct indexing
 * does, so existing comparison/assignment code is unchanged.
 *
 * RHS comparison operands requiring a second indexed read must be staged
 * separately: don't clobber A while computing the second address.
 */
char nd_wide_index_read(char area,char symbol,
                        unsigned index_node,char mode,char rhs_target)
{
    unsigned base;
    unsigned leaf;
    unsigned displacement;
    char width;
    char element_type;
    int index;
    int array;
    if(area!=1 | global_kind[symbol]!=2 | mode!=0) {
        nd_error=34;return 0;
    }
    element_type=global_type[symbol];
    if(element_type!=1 & element_type!=2 & element_type!=3) {
        nd_error=34;return 0;
    }
    leaf=index_node;
    displacement=0;
    if(nc2_kind[leaf]==6 &
       (nc2_a[leaf]=='+' | nc2_a[leaf]=='-')) {
        base=nc2_left[leaf];
        if(nc2_kind[nc2_right[leaf]]!=1) {
            nd_error=34;return 0;
        }
        displacement=nc2_number[nc2_right[leaf]];
        if(nc2_a[leaf]=='-') displacement=(0-displacement)&65535;
        leaf=base;
    }
    if(nc2_kind[leaf]!=2) {nd_error=34;return 0;}
    if(nc2_number[leaf]==1) {
        index=nd_scalar(leaf);
        width=4+type_size(element_type); /* byte index, typed stride */
    } else if(nc2_number[leaf]==2 | nc2_number[leaf]==3) {
        index=nd_word(leaf);
        width=type_size(element_type); /* word index, typed stride */
    } else {nd_error=34;return 0;}
    if(index<0) return 0;
    array=nd_record(1,symbol,2);
    if(array<0) return 0;
    nd_wide_index_used=1;
    if(nd_add(74,array,index,width,displacement)==0) return 0;
    if(element_type==1) {
        if(rhs_target!=0) {nd_error=34;return 0;}
        return nd_add(76,0,0,0,0);
    }
    if(rhs_target!=0) return nd_add(82,0,0,0,0);
    return nd_add(78,0,0,0,0);
}

/* Lower a left-associated sequence of + and - operators as a 16-bit
 * accumulator with its initial value read before the destination is written.
 * In particular, "a = a + b + a" must read the old a on the last term.
 * Only pure scalar/literal leaves are accepted; more general expression
 * trees and calls are rejected rather than reordered.
 */
char nd_chain(unsigned expr, char result_type, int dest, char returning)
{
    unsigned current;
    unsigned right;
    unsigned n;
    unsigned j;
    int value;
    char kind;
    char id;
    unsigned literal;

    current=expr;
    n=0;
    while(nc2_kind[current]==6 &
          (nc2_a[current]=='+' | nc2_a[current]=='-')) {
        if(n>=32) { nd_error=31;return 0; }
        nd_chain_right[n]=nc2_right[current];
        nd_chain_sign[n]=nc2_a[current];
        n=n+1;
        current=nc2_left[current];
        if(current==0) { nd_error=31;return 0; }
    }
    if(n==0) { nd_error=31;return 0; }
    if(nc2_kind[current]==1) {
        kind=1;
        id=0;
        literal=nc2_number[current];
    } else if(nc2_kind[current]==2) {
        if(nc2_number[current]==1) kind=2;
        else if(nc2_number[current]==2 | nc2_number[current]==3)
            kind=3;
        else {nd_error=31;return 0;}
        value=nd_record(nc2_a[current],nc2_b[current],1);
        if(value<0) return 0;
        id=value;
        literal=0;
    } else if(nc2_kind[current]==6 & nc2_a[current]=='*' &
              nc2_kind[nc2_left[current]]==2 &
              nc2_kind[nc2_right[current]]==1 &
              (nc2_number[nc2_left[current]]==2 |
               nc2_number[nc2_left[current]]==3)) {
        /* The decimal grammar uses a word times literal ten as the
         * beginning of a left-associated +/- chain. The 6502 emitter
         * implements the constant 10 with an 8x+2x shift/add, leaving
         * the product in the same two-byte arithmetic accumulator. */
        value=nd_word(nc2_left[current]);
        if(value<0) return 0;
        if(nd_add(50,3,value,0,0)==0) return 0;
        if(nd_add(96,0,0,0,nc2_number[nc2_right[current]])==0)
            return 0;
        kind=4; /* scratch accumulator already initialized */
    } else if(nc2_kind[current]==4 & nc2_a[current]==1 &
              nc2_number[current]==2 &
              (global_type[nc2_b[current]]==2 |
               global_type[nc2_b[current]]==3)) {
        if(nd_wide_index_read(nc2_a[current],nc2_b[current],
                              nc2_left[current],0,0)==0) return 0;
        kind=4; /* already materialized full word in __tacc */
    } else {nd_error=31;return 0;}
    if(kind!=4) {
        if(nd_add(50,kind,id,0,literal)==0) return 0;
    }
    j=n;
    while(j!=0) {
        j=j-1;
        right=nd_chain_right[j];
        if(nc2_kind[right]==1) {
            kind=1;
            id=0;
            literal=nc2_number[right];
        } else if(nc2_kind[right]==2) {
            if(nc2_number[right]==1) kind=2;
            else if(nc2_number[right]==2 | nc2_number[right]==3)
                kind=3;
            else {nd_error=31;return 0;}
            value=nd_record(nc2_a[right],nc2_b[right],1);
            if(value<0) return 0;
            id=value;
            literal=0;
        } else if((nc2_kind[right]==4 |
                    nc2_kind[right]==5) &
                  nc2_number[right]==1) {
            /* A byte pointer/array load is a zero-extended arithmetic
             * operand. Stage A in the independent RHS word scratch
             * before ADC/SBC consumes the full expression in __tacc. */
            if(nd_index(right,0)==0) return 0;
            if(nd_add(97,0,0,0,0)==0) return 0;
            kind=4;
            id=0;
            literal=0;
        } else if(nc2_kind[right]==4 & nc2_a[right]==1 &
                  nc2_number[right]==2 &
                  (global_type[nc2_b[right]]==2 |
                   global_type[nc2_b[right]]==3)) {
            /* The left value remains in __tacc. Address and load this
             * array term into independent __targ, then execute ADC/SBC.
             * The index address scratch never aliases either value. */
            if(nd_wide_index_read(nc2_a[right],nc2_b[right],
                                  nc2_left[right],0,1)==0) return 0;
            kind=4;
            id=0;
            literal=0;
        } else {nd_error=31;return 0;}
        if(nd_add(51,nd_chain_sign[j],kind,id,literal)==0) return 0;
    }
    if(returning==2) return 1; /* leave full expression in __tacc */
    if(returning==1) return nd_add(53,result_type,0,0,0);
    return nd_add(52,dest,result_type,0,0);
}

/* All indexed operations share one address decision: fixed byte array
 * indexed by X/Y, or a byte pointer indexed by Y.  Mode is load, compare,
 * or store.  No source-loop pattern matching is involved.
 */
char nd_index_address(char area, char symbol, char kind,
                      unsigned index_node, char mode)
{
    unsigned base_node;
    unsigned offset_node;
    int idx;
    int arr;
    int ptr;
    int owner;
    char opcode;

    if(kind==2 & nc2_kind[index_node]==6 &
       (nc2_a[index_node]=='+' | nc2_a[index_node]=='-') &
       nc2_kind[nc2_left[index_node]]==2 &
       nc2_kind[nc2_right[index_node]]==1)
        return nd_wide_index_read(area,symbol,index_node,mode,0);
    if(kind==2 & nc2_kind[index_node]==2 &
       (nc2_number[index_node]==2 | nc2_number[index_node]==3))
        return nd_wide_index_read(area,symbol,index_node,mode,0);
    if (kind != 2) {
        /* A named char pointer. The original parser checked indexing
         * syntax; verify the element really is a byte here as well. */
        if (area == 1) {
            if (global_type[symbol] != 4 | global_kind[symbol] != 1) {
                nd_error=12; return 0;
            }
        } else {
            if (local_type[symbol] != 4) { nd_error=12; return 0; }
        }
        ptr=nd_pointer(area,symbol);
        if(ptr<0) return 0;
        if(nc2_kind[index_node]==1) {
            /* A literal pointer offset is a Y immediate, not a
             * fabricated byte variable. Preserve the source's
             * constant offset and any existing live loop index. */
            if(nc2_number[index_node]>255) {nd_error=12;return 0;}
            if(mode==0) opcode=83;
            else if(mode==1) opcode=84;
            else opcode=85;
            return nd_add(opcode,ptr,0,0,nc2_number[index_node]);
        }
        idx=nd_scalar(index_node);
        if (idx<0) return 0;
        if (mode==0) opcode=6;
        else if (mode==1) opcode=7;
        else opcode=20;
        return nd_add(opcode,0,ptr,idx,0);
    }
    arr=nd_array(area,symbol);
    if (arr<0) return 0;
    if (nc2_kind[index_node]==2) {
        idx=nd_scalar(index_node);
        if (idx<0) return 0;
        if (mode==0) opcode=4;
        else if (mode==1) opcode=5;
        else opcode=19;
        return nd_add(opcode,0,arr,idx,0);
    }

    /* A computed fixed-record base and an independent character offset.
     * Reuse the pointer prepared by the earlier scalar assignment. */
    if (nc2_kind[index_node]!=6 | nc2_a[index_node]!='+') {
        nd_error=13; return 0;
    }
    base_node=nc2_left[index_node];
    offset_node=nc2_right[index_node];
    if (nc2_kind[base_node]!=2) { nd_error=13; return 0; }
    owner=nd_find(nc2_a[base_node],nc2_b[base_node]);
    if(owner<0 | nd_map_kind[owner]!=4) {
        /* General byte-array subscript: a full word offset plus a
         * byte cursor. This is not the separate fixed-record scaling
         * representation used by the original traversal experiments. */
        if(nc2_number[base_node]!=2 & nc2_number[base_node]!=3)
            {nd_error=13;return 0;}
        ptr=nd_word(base_node);
        idx=nd_scalar(offset_node);
        if(ptr<0 | idx<0) return 0;
        if(mode!=0) {nd_error=13;return 0;}
        nd_wide_index_used=1;
        if(nd_add(89,arr,ptr,idx,0)==0) return 0;
        return nd_add(76,0,0,0,0);
    }
    if (nd_map_event[owner]>=tb_count) { nd_error=14; return 0; }
    if (tb_a[nd_map_event[owner]]!=0 & tb_a[nd_map_event[owner]]!=arr) {
        nd_error=15; return 0;
    }
    tb_a[nd_map_event[owner]]=arr;
    idx=nd_scalar(offset_node);
    if (idx<0) return 0;
    if (mode==0) opcode=6;
    else if (mode==1) opcode=7;
    else opcode=20;
    return nd_add(opcode,0,nd_map_id[owner],idx,0);
}

char nd_index(unsigned node, char mode)
{
    unsigned base_node;
    if (nc2_kind[node]==4) {
        if(nc2_number[node]==2 & nc2_a[node]==1 &
           global_type[nc2_b[node]]!=1)
            return nd_wide_index_read(nc2_a[node],nc2_b[node],
                                      nc2_left[node],mode,0);
        return nd_index_address(nc2_a[node],nc2_b[node],
                                nc2_number[node],nc2_left[node],mode);
    }
    if (nc2_kind[node]==5) {
        base_node=nc2_left[node];
        if (nc2_kind[base_node]!=2 | nc2_number[base_node]!=4) {
            nd_error=12; return 0;
        }
        return nd_index_address(nc2_a[base_node],nc2_b[base_node],
                                1,nc2_right[node],mode);
    }
    nd_error=11;
    return 0;
}

/* A true 16-bit index cannot fit in 6502 X/Y. Compute the full address
 * once from the original global-array base, scaling by the element width,
 * then use (zp),Y at Y=0/1. The parser already guarantees the types.
 * The native emitter currently reserves ZP slot 0 for this cursor only
 * in functions without another indirect pointer cursor.
 */
char nd_wide_index_store(char area, char symbol, unsigned index_node,
                         unsigned rhs, char element_type)
{
    unsigned leaf;
    unsigned displacement;
    unsigned operand;
    unsigned mask;
    unsigned mask_node;
    unsigned shift_node;
    unsigned literal;
    int array;
    int index;
    int source;
    char stride;
    char kind;
    char masked;
    char shifted;
    if(area!=1 | global_kind[symbol]!=2 |
       (element_type!=1 & element_type!=2 & element_type!=3)) {
        nd_error=32; return 0;
    }
    leaf=index_node;
    displacement=0;
    if(nc2_kind[leaf]==6 &
       (nc2_a[leaf]=='+' | nc2_a[leaf]=='-')) {
        mask_node=nc2_right[leaf];
        if(nc2_kind[mask_node]!=1) {nd_error=32;return 0;}
        displacement=nc2_number[mask_node];
        if(nc2_a[leaf]=='-') displacement=(0-displacement)&65535;
        leaf=nc2_left[leaf];
    }
    if(nc2_kind[leaf]!=2) {nd_error=32;return 0;}
    stride=type_size(element_type);
    if(nc2_number[leaf]==1) {
        index=nd_scalar(leaf);
        stride=stride+4; /* zero-extended byte index */
    } else if(nc2_number[leaf]==2 | nc2_number[leaf]==3) {
        index=nd_word(leaf);
    } else {nd_error=32;return 0;}
    if(index<0) return 0;
    array=nd_record(1,symbol,2);
    if(array<0) return 0;
    nd_wide_index_used=1;
    if(nd_add(74,array,index,stride,displacement)==0) return 0;

    operand=rhs;
    mask=255;
    masked=0;
    shifted=0;
    /* All arithmetic here is a pure scalar read. Defer the read until
     * after computing the indexed address; no stack temporaries. */
    if(nc2_kind[operand]==6 & nc2_a[operand]=='&') {
        mask_node=nc2_right[operand];
        if(nc2_kind[mask_node]!=1) {nd_error=32;return 0;}
        if(nc2_number[mask_node]==65535) {
            operand=nc2_left[operand]; /* 16-bit identity */
        } else {
            if(element_type!=1) {nd_error=32;return 0;}
            mask=nc2_number[mask_node]&255;
            operand=nc2_left[operand];
            masked=1;
        }
    }
    if(nc2_kind[operand]==6 & nc2_a[operand]==147) {
        shift_node=nc2_right[operand];
        if(element_type!=1 | nc2_kind[shift_node]!=1 |
           nc2_number[shift_node]!=8) {
            nd_error=32;return 0;
        }
        shifted=1;
        operand=nc2_left[operand];
    }
    literal=0;
    if(nc2_kind[operand]==1) {
        if(shifted!=0 | masked!=0) {nd_error=32;return 0;}
        kind=1;
        source=0;
        literal=nc2_number[operand];
    } else if(nc2_kind[operand]==2) {
        if(nc2_number[operand]==1) kind=2;
        else if(nc2_number[operand]==2 | nc2_number[operand]==3)
            kind=3;
        else {nd_error=32;return 0;}
        source=nd_record(nc2_a[operand],nc2_b[operand],1);
        if(source<0) return 0;
        if(shifted!=0) {
            if(kind!=3) {nd_error=32;return 0;}
            kind=6; /* value >> 8, optionally AND a low-byte mask */
            literal=mask;
        } else if(masked!=0) {
            kind=5; /* byte masked source */
            literal=mask;
        }
    } else {nd_error=32;return 0;}
    return nd_add(75,kind,source,type_size(element_type),literal);
}

/* Store to an indexed byte location. The parser has already saved both
 * sides before emission: only these pure, byte-valued RHS forms are accepted.
 */
char nd_index_store(char area,char symbol,unsigned index_node,unsigned rhs)
{
    char kind;
    int source;
    int array;
    int word_base;
    int byte_offset;
    if (rhs==0 | index_node==0) { nd_error=27; return 0; }
    /* A global byte array indexed by a full 16-bit base plus a byte
     * displacement needs a real 6502 effective address. Evaluate the
     * RHS first, keep its byte in private scratch, then compute the
     * array pointer independently of any named char* cursor. This is
     * the same addressing operation as a wide array load, not a
     * special treatment for the assembler's symbol tables. */
    if(area==1 & global_kind[symbol]==2 & global_type[symbol]==1 &
       nc2_kind[index_node]==6 & nc2_a[index_node]=='+' &
       nc2_kind[nc2_left[index_node]]==2 &
       (nc2_number[nc2_left[index_node]]==2 |
        nc2_number[nc2_left[index_node]]==3) &
       nc2_kind[nc2_right[index_node]]==2 &
       nc2_number[nc2_right[index_node]]==1) {
        if(nc2_kind[rhs]==1) {
            if(nc2_number[rhs]>255) {nd_error=27;return 0;}
            if(nd_add(21,0,0,0,nc2_number[rhs])==0) return 0;
        } else if(nc2_kind[rhs]==2 & nc2_number[rhs]==1) {
            source=nd_scalar(rhs);
            if(source<0) return 0;
            if(nd_add(15,0,source,0,0)==0) return 0;
        } else if(nc2_kind[rhs]==4 | nc2_kind[rhs]==5) {
            if(nd_index(rhs,0)==0) return 0;
        } else {nd_error=27;return 0;}
        if(nd_add(88,0,0,0,0)==0) return 0;
        word_base=nd_word(nc2_left[index_node]);
        byte_offset=nd_scalar(nc2_right[index_node]);
        array=nd_array(area,symbol);
        if(word_base<0 | byte_offset<0 | array<0) return 0;
        nd_wide_index_used=1;
        if(nd_add(89,array,word_base,byte_offset,0)==0) return 0;
        return nd_add(90,0,0,0,0);
    }
    if(area==1 & global_kind[symbol]==2 &
       ((nc2_kind[index_node]==2 &
         (global_type[symbol]!=1 |
          nc2_number[index_node]==2 |
          nc2_number[index_node]==3)) |
        (nc2_kind[index_node]==6 &
         (nc2_a[index_node]=='+' | nc2_a[index_node]=='-') &
         nc2_kind[nc2_left[index_node]]==2 &
         nc2_kind[nc2_right[index_node]]==1)))
        return nd_wide_index_store(area,symbol,index_node,rhs,
                                   global_type[symbol]);
    if (area==1) kind=global_kind[symbol];
    else kind=1;
    if (kind!=2) {
        if (area==1) {
            if (global_type[symbol]!=4) { nd_error=27; return 0; }
        } else {
            if (local_type[symbol]!=4) { nd_error=27; return 0; }
        }
    } else if (global_type[symbol]!=1) {
        nd_error=27; return 0;
    }

    if (nc2_kind[rhs]==1) {
        if (nc2_number[rhs]>255) { nd_error=27; return 0; }
        if (nd_add(21,0,0,0,nc2_number[rhs])==0) return 0;
    } else if (nc2_kind[rhs]==2) {
        source=nd_scalar(rhs);
        if (source<0) return 0;
        if (nd_add(15,0,source,0,0)==0) return 0;
    } else if (nc2_kind[rhs]==4 | nc2_kind[rhs]==5) {
        if (nd_index(rhs,0)==0) return 0;
    } else if (nc2_kind[rhs]==8) {
        if (nd_add(25,0,0,0,0)==0) return 0; /* call result in A */
    } else {
        nd_error=27; return 0;
    }
    return nd_index_address(area,symbol,kind,index_node,2);
}

/* Calls are effects in the original parser's event order. Stage zero,
 * one or two independently type-checked byte operands left-to-right using
 * the callee's ordinary static Nano C argument homes. Complex/nested call
 * expressions remain rejected by the semantic parser.
 */
char nd_call(unsigned node, char callee)
{
    char argc;
    char i;
    unsigned argument;
    int value;
    char expected;
    char actual;
    char staged;
    if(node==0 | nc2_kind[node]!=8 | nc2_a[node]!=callee |
       nc2_b[node]>8) {nd_error=28;return 0;}
    argc=nc2_b[node];
    i=0;
    while(i<argc) {
        argument=nc2_call_values[nc2_number[node]+i];
        if(argument==0) {nd_error=28;return 0;}
        expected=param_type[global_param_start[callee]+i];
        staged=0;
        if(expected==1) {
            if(nc2_kind[argument]==1) {
                if(nd_add(21,0,0,0,nc2_number[argument]&255)==0)
                    return 0;
            } else if(nc2_kind[argument]==2) {
                actual=nc2_number[argument];
                if(actual==1) {
                    value=nd_scalar(argument);
                    if(value<0) return 0;
                    if(nd_add(15,0,value,0,0)==0) return 0;
                } else if(actual==2 | actual==3) {
                    value=nd_word(argument);
                    if(value<0) return 0;
                    if(nd_add(47,callee,i,value,0)==0) return 0;
                    staged=1;
                } else {nd_error=28;return 0;}
            } else if(nc2_kind[argument]==4 | nc2_kind[argument]==5) {
                if(nd_index(argument,0)==0) return 0;
            } else {nd_error=28;return 0;}
            if(staged==0) {
                if(nd_add(22,callee,i,0,0)==0) return 0;
            }
        } else if(expected==2 | expected==3) {
            if(nc2_kind[argument]==1) {
                if(nd_add(44,callee,i,0,nc2_number[argument])==0)
                    return 0;
            } else if(nc2_kind[argument]==2) {
                actual=nc2_number[argument];
                if(actual==2 | actual==3) {
                    value=nd_word(argument);
                    if(value<0) return 0;
                    if(nd_add(45,callee,i,value,0)==0) return 0;
                } else if(actual==1) {
                    value=nd_scalar(argument);
                    if(value<0) return 0;
                    if(nd_add(46,callee,i,value,0)==0) return 0;
                } else {nd_error=28;return 0;}
            } else if(nc2_kind[argument]==6) {
                /* The word argument is evaluated into the private
                 * two-byte accumulator, then copied into its static
                 * callee slot *before* evaluating the next argument.
                 * An identity AND $FFFF changes neither value nor
                 * evaluation order. */
                if(nc2_a[argument]=='&' &
                   nc2_kind[nc2_right[argument]]==1 &
                   nc2_number[nc2_right[argument]]==65535)
                    argument=nc2_left[argument];
                if(nd_chain(argument,2,0,2)==0) return 0;
                if(nd_add(77,callee,i,0,0)==0) return 0;
            } else {nd_error=28;return 0;}
        } else if(expected==4) {
            if(nc2_kind[argument]!=2 | nc2_number[argument]!=4) {
                nd_error=28;return 0;
            }
            /* A pointer is an ordinary two-byte static Phase-1 value
             * when passed. Its dereference cursor is separate state
             * that must be reconciled across the eventual JSR. */
            if(nd_add(86,callee,i,nc2_a[argument],nc2_b[argument])==0)
                return 0;
        } else {nd_error=28;return 0;}
        i=i+1;
    }
    return nd_add(23,callee,global_type[callee],0,0);
}

/* Mixed comparisons use one numeric descriptor consumed by the 6502
 * emitter: left/right kinds 1 literal, 2 byte, 3 word; bit 6 unsigned.
 * The original parser determines unsigned promotion. A home of zero is
 * reserved for an arithmetic expression in the two-byte __tacc scratch. */
char nd_numeric_compare(char left_kind, char left_home,
                        char right_kind, char right_home,
                        char unsigned_compare, unsigned literal)
{
    char descriptor;
    descriptor=(left_kind<<3) | right_kind;
    if(unsigned_compare!=0) descriptor=descriptor | 64;
    return nd_add(68,left_home,right_home,descriptor,literal);
}

char nd_condition_word(char left_id, unsigned right, char unsigned_compare)
{
    int r;
    unsigned literal;
    /* A signed negative integer constant is still a 16-bit scalar
     * operand. Preserve all bits; comparing only its low byte would
     * incorrectly conflate -2 with 254. */
    if(nc2_kind[right]==7 & nc2_kind[nc2_left[right]]==1) {
        literal=(0-nc2_number[nc2_left[right]])&65535;
        if(left_id!=0)
            return nd_add(40,left_id,unsigned_compare,0,literal);
        return nd_numeric_compare(3,0,1,0,unsigned_compare,literal);
    }
    if(nc2_kind[right]==1) {
        if(left_id!=0)
            return nd_add(40,left_id,unsigned_compare,0,nc2_number[right]);
        return nd_numeric_compare(3,0,1,0,unsigned_compare,
                                  nc2_number[right]);
    }
    if(nc2_kind[right]!=2) {nd_error=18;return 0;}
    if(nc2_number[right]==1) {
        r=nd_scalar(right);
        if(r<0) return 0;
        return nd_numeric_compare(3,left_id,2,r,unsigned_compare,0);
    }
    r=nd_word(right);
    if(r<0) return 0;
    if(left_id!=0) return nd_add(39,left_id,r,unsigned_compare,0);
    return nd_numeric_compare(3,0,3,r,unsigned_compare,0);
}

char nd_condition(unsigned expr, unsigned exit_label)
{
    unsigned left;
    unsigned right;
    char op;
    char rel;
    int l;
    int r;
    if(expr==0) {nd_error=16;return 0;}
    if(nc2_kind[expr]==2) {
        if(nc2_number[expr]==2 | nc2_number[expr]==3) {
            l=nd_word(expr);
            if(l<0) return 0;
            if(nd_add(41,l,0,0,0)==0) return 0;
        } else {
            l=nd_scalar(expr);
            if(l<0) return 0;
            if(nd_add(8,l,0,0,0)==0) return 0;
        }
        return nd_add(10,0,1,0,exit_label);
    }
    if(nc2_kind[expr]!=6) {nd_error=16;return 0;}
    op=nc2_a[expr];
    if(op=='+' | op=='-') {
        if(nd_chain(expr,2,0,2)==0) return 0;
        if(nd_add(69,0,0,0,0)==0) return 0;
        return nd_add(10,0,1,0,exit_label);
    }
    if(op==142) rel=2;        /* ==: false when NE */
    else if(op==143) rel=1;   /* !=: false when EQ */
    else if(op=='<') rel=4;   /* <: false when carry set */
    else if(op==145) rel=3;   /* >=: false when carry clear */
    else if(op=='>') rel=5;   /* >: false when <= */
    else if(op==144) rel=6;   /* <=: false when > */
    else {nd_error=17;return 0;}
    left=nc2_left[expr];
    right=nc2_right[expr];
    /* A word array element is already a full C integer. Read it
     * through its 16-bit indexed pointer into __tacc, then compare
     * against a scalar or literal with the same typed comparator as
     * ordinary word expressions; do not narrow it to the byte in A. */
    if(nc2_kind[left]==4 & nc2_a[left]==1 &
       nc2_number[left]==2 &
       (global_type[nc2_b[left]]==2 | global_type[nc2_b[left]]==3)) {
        if(nd_index(left,0)==0) return 0;
        if(nd_condition_word(0,right,nc2_b[expr])==0) return 0;
        return nd_add(10,0,rel,0,exit_label);
    }
    if(nc2_kind[left]==6 &
       (nc2_a[left]=='+' | nc2_a[left]=='-')) {
        if(nd_chain(left,2,0,2)==0) return 0;
        if(nd_condition_word(0,right,nc2_b[expr])==0) return 0;
        return nd_add(10,0,rel,0,exit_label);
    }
    if(nc2_kind[left]==2 &
       (nc2_number[left]==2 | nc2_number[left]==3)) {
        l=nd_word(left);
        if(l<0) return 0;
        if(nd_condition_word(l,right,nc2_b[expr])==0) return 0;
        return nd_add(10,0,rel,0,exit_label);
    }
    if(nc2_kind[left]==1 & nc2_kind[right]==2) {
        if(nc2_number[right]==1) {
            r=nd_scalar(right);
            if(r<0) return 0;
            if(nd_numeric_compare(1,0,2,r,nc2_b[expr],
                                  nc2_number[left])==0) return 0;
        } else {
            r=nd_word(right);
            if(r<0) return 0;
            if(nd_numeric_compare(1,0,3,r,nc2_b[expr],
                                  nc2_number[left])==0) return 0;
        }
        return nd_add(10,0,rel,0,exit_label);
    }
    if(nc2_kind[left]==2 & nc2_number[left]==1) {
        l=nd_scalar(left);
        if(l<0) return 0;
        if(nc2_kind[right]==2 &
           (nc2_number[right]==2 | nc2_number[right]==3)) {
            r=nd_word(right);
            if(r<0) return 0;
            if(nd_numeric_compare(2,l,3,r,nc2_b[expr],0)==0) return 0;
            return nd_add(10,0,rel,0,exit_label);
        }
        if(nc2_kind[right]==1) {
            if(nc2_number[right]>255) {
                if(nd_numeric_compare(2,l,1,0,nc2_b[expr],
                                      nc2_number[right])==0) return 0;
            } else {
                if(nd_add(8,l,0,0,nc2_number[right])==0) return 0;
            }
        } else if(nc2_kind[right]==2) {
            r=nd_scalar(right);
            if(r<0) return 0;
            if(nd_add(9,l,r,0,0)==0) return 0;
        } else {nd_error=18;return 0;}
    } else if(nc2_kind[left]==4 | nc2_kind[left]==5) {
        if(nd_index(left,0)==0) return 0;
        if(nc2_kind[right]==4 | nc2_kind[right]==5) {
            if(nd_index(right,1)==0) return 0;
        } else if(nc2_kind[right]==2) {
            if(nc2_number[right]==2 | nc2_number[right]==3) {
                /* The array's byte in A is promoted to a full int,
                 * not truncated to the low byte of the RHS word. */
                r=nd_word(right);
                if(r<0) return 0;
                if(nd_add(88,0,0,0,0)==0) return 0;
                if(nd_numeric_compare(2,0,3,r,nc2_b[expr],0)==0)
                    return 0;
            } else {
                r=nd_scalar(right);
                if(r<0) return 0;
                if(nd_add(18,0,r,0,0)==0) return 0;
            }
        } else if(nc2_kind[right]==1) {
            if(nc2_number[right]>255) {nd_error=18;return 0;}
            if(nd_add(17,0,0,0,nc2_number[right])==0) return 0;
        } else {nd_error=18;return 0;}
    } else {nd_error=18;return 0;}
    return nd_add(10,0,rel,0,exit_label);
}

char nd_assignment(char area, char symbol, unsigned rhs)
{
    char target_type;
    int dst;
    int src;
    int ptr;
    int entry;
    unsigned lhs;
    unsigned extra;
    unsigned left_term;
    unsigned right_term;
    unsigned shift;
    unsigned literal;
    int left_home;
    int right_home;
    char right_kind;
    char op;
    if (rhs==0) { nd_error=19; return 0; }
    if (area==1) target_type=global_type[symbol];
    else target_type=local_type[symbol];
    /* A Phase-1 value is at most 16 bits. AND $FFFF is an identity
     * for any numeric subexpression, including nested subtraction.
     * This avoids a gratuitous temporary when ass.c writes
     * difference = (target - base) & 65535. */
    if((target_type==1 | target_type==2 | target_type==3) &
       nc2_kind[rhs]==6 & nc2_a[rhs]=='&' &
       nc2_kind[nc2_right[rhs]]==1 &
       nc2_number[nc2_right[rhs]]==65535)
        rhs=nc2_left[rhs];
    if (nc2_kind[rhs]==6) {
        op=nc2_a[rhs];
        lhs=nc2_left[rhs];
        extra=nc2_right[rhs];
        if (op=='+' & target_type==1 & nc2_kind[lhs]==2 & nc2_kind[extra]==1 &
            nc2_number[extra]==1 & nc2_a[lhs]==area &
            nc2_b[lhs]==symbol) {
            dst=nd_record(area,symbol,1);
            if (dst<0) return 0;
            return nd_add(3,dst,0,0,0);
        }
        if (op=='*' & target_type==2 & nc2_kind[lhs]==2 & nc2_kind[extra]==1) {
            /* C source recurrence: base = index * constant stride.
             * Keep a ZP pointer representation, but only when an indexed
             * use later establishes its unique array owner.
             */
            src=nd_scalar(lhs);
            if (src<0) return 0;
            ptr=nd_record(area,symbol,4);
            if (ptr<0) return 0;
            entry=nd_find(area,symbol);
            if (entry<0) return 0;
            nd_map_event[entry]=tb_count;
            return nd_add(14,ptr,0,src,nc2_number[extra]);
        }
    }
    if(target_type==2 | target_type==3) {
        dst=nd_record(area,symbol,1);
        if(dst<0) return 0;
        if(nc2_kind[rhs]==1) {
            return nd_add(27,dst,0,0,nc2_number[rhs]);
        }
        /* Unary negation of a literal is a constant, not a runtime
         * expression tree. Phase-1 words wrap modulo 65536. */
        if(nc2_kind[rhs]==7 & nc2_kind[nc2_left[rhs]]==1)
            return nd_add(27,dst,0,0,(0-nc2_number[nc2_left[rhs]])&65535);
        if(nc2_kind[rhs]==8) {
            if(global_type[nc2_a[rhs]]==2)
                return nd_add(42,dst,0,0,0);
            if(global_type[nc2_a[rhs]]==1)
                return nd_add(48,dst,0,0,0);
            nd_error=25;return 0;
        }
        if((nc2_kind[rhs]==4 | nc2_kind[rhs]==5) &
           nc2_number[rhs]==1) {
            /* A byte array/pointer element assigned to an int/unsigned
             * is zero-extended. The address operation leaves the byte
             * in A; no byte temporary or memory indexing shortcut. */
            if(nd_index(rhs,0)==0) return 0;
            return nd_add(95,dst,0,0,0);
        }
        if(nc2_kind[rhs]==4 & nc2_a[rhs]==1 &
           nc2_number[rhs]==2 &
           (global_type[nc2_b[rhs]]==2 |
            global_type[nc2_b[rhs]]==3)) {
            if(nd_index(rhs,0)==0) return 0;
            return nd_add(79,dst,0,0,0);
        }
        if(nc2_kind[rhs]==2) {
            if(nc2_number[rhs]==1) {
                src=nd_scalar(rhs);
                if(src<0) return 0;
                return nd_add(54,dst,src,0,0); /* zero-extend byte */
            }
            src=nd_word(rhs);
            if(src<0) return 0;
            if(src==dst) return 1; /* an in-place identity is no work */
            return nd_add(28,dst,src,0,0);
        }
        /* A little-endian byte pair packed as low | (high << 8)
         * is simply two direct byte reads and stores on the 6502.
         * This common Phase-1 expression has no side effects, and
         * neither byte overlaps the other in the resulting word. */
        if(nc2_kind[rhs]==6 & nc2_a[rhs]=='|' &
           (nc2_kind[nc2_left[rhs]]==4 |
            nc2_kind[nc2_left[rhs]]==5) &
           nc2_kind[nc2_right[rhs]]==6 &
           nc2_a[nc2_right[rhs]]==146 &
           (nc2_kind[nc2_left[nc2_right[rhs]]]==4 |
            nc2_kind[nc2_left[nc2_right[rhs]]]==5) &
           nc2_kind[nc2_right[nc2_right[rhs]]]==1 &
           nc2_number[nc2_right[nc2_right[rhs]]]==8) {
            if(nd_index(nc2_left[rhs],0)==0) return 0;
            if(nd_add(91,dst,0,0,0)==0) return 0;
            if(nd_index(nc2_left[nc2_right[rhs]],0)==0) return 0;
            return nd_add(92,dst,0,0,0);
        }
        /* A left-shifted 16-bit scalar OR another scalar/literal is
         * just a word in two byte lanes: load into the existing scratch
         * accumulator, ASL/ROL the desired number of bits, then OR in
         * the second value before committing the result. Keeping the
         * final store last also handles result/source aliasing.
         * E.g. value = (value << 4) | digit in the assembler parser. */
        if(nc2_kind[rhs]==6 & nc2_a[rhs]=='|') {
            left_term=nc2_left[rhs];
            right_term=nc2_right[rhs];
            shift=0;
            if(nc2_kind[left_term]==6 & nc2_a[left_term]==146) {
                if(nc2_kind[nc2_right[left_term]]!=1) {
                    nd_error=25;return 0;
                }
                shift=nc2_number[nc2_right[left_term]];
                left_term=nc2_left[left_term];
            }
            if(shift>15 | nc2_kind[left_term]!=2 |
               (nc2_number[left_term]!=2 & nc2_number[left_term]!=3)) {
                nd_error=25;return 0;
            }
            left_home=nd_word(left_term);
            if(left_home<0) return 0;
            if(nd_add(50,3,left_home,0,0)==0) return 0;
            if(shift!=0 & nd_add(93,0,0,0,shift)==0) return 0;
            right_home=0;
            literal=0;
            if(nc2_kind[right_term]==1) {
                right_kind=1;
                literal=nc2_number[right_term];
            } else if(nc2_kind[right_term]==2) {
                if(nc2_number[right_term]==1) {
                    right_kind=2;
                    right_home=nd_scalar(right_term);
                } else if(nc2_number[right_term]==2 |
                          nc2_number[right_term]==3) {
                    right_kind=3;
                    right_home=nd_word(right_term);
                } else {nd_error=25;return 0;}
                if(right_home<0) return 0;
            } else {nd_error=25;return 0;}
            if(nd_add(94,right_kind,right_home,0,literal)==0) return 0;
            return nd_add(52,dst,target_type,0,0);
        }
        /* A word scalar shifted by a known constant uses the same
         * two-byte ASL/ROL path without a second OR operand. */
        if(nc2_kind[rhs]==6 & nc2_a[rhs]==146 &
           nc2_kind[nc2_left[rhs]]==2 &
           (nc2_number[nc2_left[rhs]]==2 |
            nc2_number[nc2_left[rhs]]==3) &
           nc2_kind[nc2_right[rhs]]==1) {
            shift=nc2_number[nc2_right[rhs]];
            if(shift>15) {nd_error=25;return 0;}
            src=nd_word(nc2_left[rhs]);
            if(src<0) return 0;
            if(nd_add(50,3,src,0,0)==0) return 0;
            if(shift!=0 & nd_add(93,0,0,0,shift)==0) return 0;
            return nd_add(52,dst,target_type,0,0);
        }
        /* The assembler uses masks for opcode fields and 16-bit wrap.
         * Preserve ordinary C bitwise semantics, including destination
         * aliasing. & $FFFF on the same home emits no instructions. */
        if(nc2_kind[rhs]==6 & nc2_a[rhs]=='&') {
            lhs=nc2_left[rhs];
            extra=nc2_right[rhs];
            if(nc2_kind[lhs]==2 & nc2_kind[extra]==1 &
               (nc2_number[lhs]==2 | nc2_number[lhs]==3)) {
                src=nd_word(lhs);
                if(src<0) return 0;
                if(src==dst & nc2_number[extra]==65535) return 1;
                return nd_add(70,dst,src,0,nc2_number[extra]);
            }
        }
        /* Word +/- literal uses the 6502 carry chain directly.
         * The source can be the destination: low-byte write leaves the
         * source high byte and the processor carry/borrow intact. */
        if(nc2_kind[rhs]==6 &
           (nc2_a[rhs]=='+' | nc2_a[rhs]=='-')) {
            lhs=nc2_left[rhs];
            extra=nc2_right[rhs];
            if(nc2_kind[extra]==1 & nc2_kind[lhs]==2 &
               (nc2_number[lhs]==2 | nc2_number[lhs]==3)) {
                src=nd_word(lhs);
                if(src<0) return 0;
                if(nc2_a[rhs]=='+') op=31;
                else op=32;
                return nd_add(op,dst,src,0,nc2_number[extra]);
            }
            if(nc2_kind[extra]==2) {
                /* A byte index is promoted to 16 bits by zero extension. */
                if(nc2_kind[lhs]==2 &
                   (nc2_number[lhs]==2 | nc2_number[lhs]==3) &
                   nc2_number[extra]==1) {
                    src=nd_word(lhs);
                    if(src<0) return 0;
                    ptr=nd_scalar(extra);
                    if(ptr<0) return 0;
                    if(nc2_a[rhs]=='+') op=58;
                    else op=59;
                    return nd_add(op,dst,src,ptr,0);
                }
                if(nc2_kind[lhs]==2 & nc2_number[lhs]==1 &
                   (nc2_number[extra]==2 | nc2_number[extra]==3)) {
                    src=nd_scalar(lhs);
                    if(src<0) return 0;
                    ptr=nd_word(extra);
                    if(ptr<0) return 0;
                    if(nc2_a[rhs]=='+') return nd_add(58,dst,ptr,src,0);
                    return nd_add(63,dst,src,ptr,0);
                }
                if(nc2_kind[lhs]==2 & nc2_number[lhs]==1 &
                   nc2_number[extra]==1 & nc2_a[rhs]=='+') {
                    src=nd_scalar(lhs);
                    if(src<0) return 0;
                    ptr=nd_scalar(extra);
                    if(ptr<0) return 0;
                    return nd_add(65,dst,src,ptr,0);
                }
                if(nc2_kind[lhs]==2 &
                   (nc2_number[lhs]==2 | nc2_number[lhs]==3) &
                   (nc2_number[extra]==2 | nc2_number[extra]==3)) {
                    src=nd_word(lhs);
                    if(src<0) return 0;
                    ptr=nd_word(extra);
                    if(ptr<0) return 0;
                    if(nc2_a[rhs]=='+') op=35;
                    else op=36;
                    return nd_add(op,dst,src,ptr,0);
                }
            }
            /* More than one arithmetic operation, reversed mixed-width
             * operands, or byte + byte: use the bounded numeric chain. */
            return nd_chain(rhs,target_type,dst,0);
        }
        nd_error=25;return 0;
    }
    if (target_type!=1) { nd_error=25; return 0; }
    dst=nd_record(area,symbol,1);
    if (dst<0) return 0;
    if (nc2_kind[rhs]==1) {
        if (nc2_number[rhs]>255) { nd_error=20; return 0; }
        return nd_add(2,dst,0,0,nc2_number[rhs]);
    }
    if(nc2_kind[rhs]==7 & nc2_kind[nc2_left[rhs]]==1)
        return nd_add(2,dst,0,0,(0-nc2_number[nc2_left[rhs]])&255);
    if (nc2_kind[rhs]==2) {
        if(nc2_number[rhs]==1) src=nd_scalar(rhs);
        else src=nd_word(rhs); /* narrowing keeps the low byte */
        if (src<0) return 0;
        if (nd_add(15,0,src,0,0)==0) return 0;
        return nd_add(16,dst,0,0,0);
    }
    if(nc2_kind[rhs]==6 &
       (nc2_a[rhs]=='+' | nc2_a[rhs]=='-')) {
        lhs=nc2_left[rhs];
        extra=nc2_right[rhs];
        if(nc2_a[rhs]=='+' & nc2_kind[lhs]==2 &
           nc2_kind[extra]==2 & nc2_number[lhs]==1 &
           nc2_number[extra]==1) {
            src=nd_scalar(lhs);
            if(src<0) return 0;
            ptr=nd_scalar(extra);
            if(ptr<0) return 0;
            return nd_add(66,dst,src,ptr,0);
        }
        return nd_chain(rhs,target_type,dst,0);
    }
    if (nc2_kind[rhs]==4 | nc2_kind[rhs]==5) {
        if (nd_index(rhs,0)==0) return 0;
        return nd_add(16,dst,0,0,0);
    }
    if (nc2_kind[rhs]==8) {
        if (nd_add(25,0,0,0,0)==0) return 0;
        return nd_add(16,dst,0,0,0);
    }
    nd_error=20;
    return 0;
}

char nd_return(unsigned expr)
{
    int src;
    unsigned lhs;
    unsigned extra;
    char op;
    if (expr==0) { nd_error=21; return 0; }
    if (nc2_return_type==2 | nc2_return_type==3) {
        if(nc2_kind[expr]==1)
            return nd_add(29,0,0,0,nc2_number[expr]);
        if(nc2_kind[expr]==7 & nc2_kind[nc2_left[expr]]==1)
            return nd_add(29,0,0,0,(0-nc2_number[nc2_left[expr]])&65535);
        if(nc2_kind[expr]==8) {
            if(global_type[nc2_a[expr]]==2)
                return nd_add(43,0,0,0,0);
            if(global_type[nc2_a[expr]]==1)
                return nd_add(49,0,0,0,0);
            nd_error=21;return 0;
        }
        if(nc2_kind[expr]==4 & nc2_a[expr]==1 &
           nc2_number[expr]==2 &
           (global_type[nc2_b[expr]]==2 |
            global_type[nc2_b[expr]]==3)) {
            if(nd_index(expr,0)==0) return 0;
            return nd_add(53,nc2_return_type,0,0,0);
        }
        if(nc2_kind[expr]==2) {
            if(nc2_number[expr]==1) {
                src=nd_scalar(expr);
                if(src<0) return 0;
                return nd_add(12,src,0,0,0); /* zero-extended A/X */
            }
            src=nd_word(expr);
            if(src<0) return 0;
            return nd_add(30,src,0,0,0);
        }
        if(nc2_kind[expr]==6 & nc2_a[expr]=='&') {
            lhs=nc2_left[expr];
            extra=nc2_right[expr];
            if(nc2_kind[lhs]==2 & nc2_kind[extra]==1 &
               (nc2_number[lhs]==2 | nc2_number[lhs]==3)) {
                src=nd_word(lhs);
                if(src<0) return 0;
                return nd_add(73,src,0,0,nc2_number[extra]);
            }
        }
        if(nc2_kind[expr]==6 & nc2_a[expr]==147) {
            lhs=nc2_left[expr];
            extra=nc2_right[expr];
            if(nc2_kind[lhs]==2 & nc2_number[lhs]==3 &
               nc2_kind[extra]==1 & nc2_number[extra]==8) {
                src=nd_word(lhs);
                if(src<0) return 0;
                return nd_add(72,src,0,0,255);
            }
        }
        if(nc2_kind[expr]==6 &
           (nc2_a[expr]=='+' | nc2_a[expr]=='-')) {
            lhs=nc2_left[expr];
            extra=nc2_right[expr];
            if(nc2_kind[extra]==1 & nc2_kind[lhs]==2 &
               (nc2_number[lhs]==2 | nc2_number[lhs]==3)) {
                src=nd_word(lhs);
                if(src<0) return 0;
                if(nc2_a[expr]=='+') op=33;
                else op=34;
                return nd_add(op,src,0,0,nc2_number[extra]);
            }
            if(nc2_kind[extra]==2) {
                if(nc2_kind[lhs]==2 &
                   (nc2_number[lhs]==2 | nc2_number[lhs]==3) &
                   nc2_number[extra]==1) {
                    src=nd_word(lhs);
                    if(src<0) return 0;
                    extra=nd_scalar(extra);
                    if(extra>31) { nd_error=30;return 0; }
                    if(nc2_a[expr]=='+') op=60;
                    else op=61;
                    return nd_add(op,0,src,extra,0);
                }
                if(nc2_kind[lhs]==2 & nc2_number[lhs]==1 &
                   (nc2_number[extra]==2 | nc2_number[extra]==3)) {
                    src=nd_scalar(lhs);
                    if(src<0) return 0;
                    extra=nd_word(extra);
                    if(extra>31) {nd_error=30;return 0;}
                    if(nc2_a[expr]=='+')
                        return nd_add(60,0,extra,src,0);
                    return nd_add(62,0,src,extra,0);
                }
                if(nc2_kind[lhs]==2 & nc2_number[lhs]==1 &
                   nc2_number[extra]==1 & nc2_a[expr]=='+') {
                    src=nd_scalar(lhs);
                    if(src<0) return 0;
                    extra=nd_scalar(extra);
                    if(extra>31) {nd_error=30;return 0;}
                    return nd_add(64,0,src,extra,0);
                }
                if(nc2_kind[lhs]==2 &
                   (nc2_number[lhs]==2 | nc2_number[lhs]==3) &
                   (nc2_number[extra]==2 | nc2_number[extra]==3)) {
                    src=nd_word(lhs);
                    if(src<0) return 0;
                    extra=nd_word(extra);
                    if(extra>31) { nd_error=30;return 0; }
                    if(nc2_a[expr]=='+') op=37;
                    else op=38;
                    return nd_add(op,0,src,extra,0);
                }
            }
            return nd_chain(expr,nc2_return_type,0,1);
        }
        nd_error=21;return 0;
    }
    if (nc2_kind[expr]==1) {
        if (nc2_number[expr]>255) { nd_error=21; return 0; }
        return nd_add(13,0,0,0,nc2_number[expr]);
    }
    if(nc2_kind[expr]==7 & nc2_kind[nc2_left[expr]]==1)
        return nd_add(13,0,0,0,(0-nc2_number[nc2_left[expr]])&255);
    if (nc2_kind[expr]==2) {
        if(nc2_number[expr]==1) src=nd_scalar(expr);
        else src=nd_word(expr); /* byte return truncates word */
        if (src<0) return 0;
        return nd_add(12,src,0,0,0);
    }
    if(nc2_kind[expr]==6) {
        lhs=nc2_left[expr];
        extra=nc2_right[expr];
        if(nc2_a[expr]=='&' & nc2_kind[extra]==1) {
            if(nc2_kind[lhs]==2 &
               (nc2_number[lhs]==1 | nc2_number[lhs]==2 |
                nc2_number[lhs]==3)) {
                src=nd_record(nc2_a[lhs],nc2_b[lhs],1);
                if(src<0) return 0;
                return nd_add(71,src,nc2_number[lhs],0,
                              nc2_number[extra]);
            }
            if(nc2_kind[lhs]==6 & nc2_a[lhs]==147 &
               nc2_kind[nc2_right[lhs]]==1 &
               nc2_number[nc2_right[lhs]]==8 &
               nc2_kind[nc2_left[lhs]]==2 &
               nc2_number[nc2_left[lhs]]==3) {
                src=nd_word(nc2_left[lhs]);
                if(src<0) return 0;
                return nd_add(72,src,0,0,nc2_number[extra]);
            }
        }
        if(nc2_a[expr]==147 & nc2_kind[extra]==1 &
           nc2_number[extra]==8 & nc2_kind[lhs]==2 &
           nc2_number[lhs]==3) {
            src=nd_word(lhs);
            if(src<0) return 0;
            return nd_add(72,src,0,0,255);
        }
    }
    if(nc2_kind[expr]==6 &
       (nc2_a[expr]=='+' | nc2_a[expr]=='-')) {
        lhs=nc2_left[expr];
        extra=nc2_right[expr];
        if(nc2_a[expr]=='+' & nc2_kind[lhs]==2 &
           nc2_kind[extra]==2 & nc2_number[lhs]==1 &
           nc2_number[extra]==1) {
            src=nd_scalar(lhs);
            if(src<0) return 0;
            extra=nd_scalar(extra);
            if(extra>31) {nd_error=30;return 0;}
            return nd_add(67,0,src,extra,0);
        }
        return nd_chain(expr,nc2_return_type,0,1);
    }
    if (nc2_kind[expr]==4 | nc2_kind[expr]==5) {
        /* A pointer/byte-array subscript is already a byte in A.
         * The native byte-result ABI returns A with X zeroed. */
        if(nd_index(expr,0)==0) return 0;
        return nd_add(26,0,0,0,0);
    }
    if (nc2_kind[expr]==8) {
        if (nd_add(25,0,0,0,0)==0) return 0;
        return nd_add(26,0,0,0,0);
    }
    nd_error=21;
    return 0;
}

char nd_prepare()
{
    unsigned i;
    char op;
    char area;
    char sym;
    unsigned node;
    unsigned label;
    nd_error=0;
    nd_map_count=0;
    nd_next_scalar=1;
    nd_next_array=1;
    nd_next_pointer=0;
    nd_wide_index_used=0;
    tb_reset();
    if (nc2_fault!=0) return 0;
    if (nc2_return_type!=1 & nc2_return_type!=2 &
        nc2_return_type!=3) { nd_error=26; return 0; }
    i=0;
    while (i<nc2_events) {
        op=nc2_event_kind[i];
        area=nc2_event_area[i];
        sym=nc2_event_symbol[i];
        node=nc2_event_node[i];
        label=nc2_event_label[i];
        nd_failure_event=i;
        if (op==1) {
            if (nd_add(1,0,0,0,label)==0) return 0;
        } else if (op==2) {
            if (nd_add(11,0,0,0,label)==0) return 0;
        } else if (op==3) {
            if (nd_condition(node,label)==0) return 0;
        } else if (op==4) {
            if (nd_assignment(area,sym,node)==0) return 0;
        } else if (op==5) {
            if (nd_return(node)==0) return 0;
        } else if (op==6) {
            if (nd_index_store(area,sym,label,node)==0) return 0;
        } else if (op==7) {
            if (nd_call(node,sym)==0) return 0;
        } else {
            nd_error=22; return 0;
        }
        i=i+1;
    }
    /* A wide indexed array uses the second ZP cursor when a named
     * pointer occupies the first; two named cursors plus a wide array
     * still cannot fit in the two available 6502 pointer registers.
     * Copy these semantic homes once for call-boundary restoration. */
    if(nd_wide_index_used!=0 & nd_next_pointer>1) {
        nd_error=33;return 0;
    }
    tb_wide_cursor=0;
    if(nd_wide_index_used!=0 & nd_next_pointer!=0) tb_wide_cursor=1;
    tb_pointer_count=nd_next_pointer;
    i=0;
    while(i<nd_next_pointer) {
        tb_pointer_area[i]=nd_ptr_area[i];
        tb_pointer_symbol[i]=nd_ptr_symbol[i];
        i=i+1;
    }
    /* Every provisional scaled-pointer operation must have an array owner. */
    i=0;
    while (i<tb_count) {
        if (tb_op[i]==14 & tb_a[i]==0) { nd_error=23; return 0; }
        i=i+1;
    }
    return 1;
}

/* The same lowering is used for host execution and native assembly.
 * Native output inserts the Nano C argument-pointer prologue between
 * semantic planning and final instruction emission. */
char nd_compile()
{
    if (nd_prepare()==0) return 0;
    if (tb_compile()==0) { nd_error=24; return 0; }
    return 1;
}
