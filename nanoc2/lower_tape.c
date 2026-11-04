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
    } else {nd_error=31;return 0;}
    if(nd_add(50,kind,id,0,literal)==0) return 0;
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
        idx=nd_scalar(index_node);
        if (ptr<0 | idx<0) return 0;
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
    owner=nd_base(nc2_a[base_node],nc2_b[base_node]);
    if (owner<0) return 0;
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

/* Store to an indexed byte location. The parser has already saved both
 * sides before emission: only these pure, byte-valued RHS forms are accepted.
 */
char nd_index_store(char area,char symbol,unsigned index_node,unsigned rhs)
{
    char kind;
    int source;
    if (rhs==0 | index_node==0) { nd_error=27; return 0; }
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
       nc2_b[node]>2) {nd_error=28;return 0;}
    argc=nc2_b[node];
    i=0;
    while(i<argc) {
        if(i==0) argument=nc2_left[node];
        else argument=nc2_right[node];
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
            } else {nd_error=28;return 0;}
        } else {nd_error=28;return 0;}
        i=i+1;
    }
    return nd_add(23,callee,global_type[callee],0,0);
}

/* Compare a numeric scalar and another scalar/literal at full C width.
 * Descriptors are packed into the existing bounded tape:
 *   d/a = physical scalar homes (if not literal)
 *   b = left-kind*8 + right-kind + 64 if usual-conversion unsigned
 *   num = the single literal, if present.
 * kind: 1 literal, 2 char scalar, 3 int/unsigned scalar.
 *
 * This is an addressing choice, not a generic expression representation.
 * Literal/literal and side-effectful operands stay rejected. */
char nd_numeric_compare(unsigned left, unsigned right, char is_unsigned)
{
    char lk;
    char rk;
    int l;
    int r;
    unsigned number;
    lk=0;
    rk=0;
    l=0;
    r=0;
    number=0;
    if(nc2_kind[left]==1) {
        lk=1;
        number=nc2_number[left];
    } else if(nc2_kind[left]==2) {
        if(nc2_number[left]==1) lk=2;
        else if(nc2_number[left]==2 | nc2_number[left]==3) lk=3;
        else {nd_error=18;return 0;}
        l=nd_record(nc2_a[left],nc2_b[left],1);
        if(l<0) return 0;
    } else {nd_error=18;return 0;}
    if(nc2_kind[right]==1) {
        if(lk==1) {nd_error=18;return 0;}
        rk=1;
        number=nc2_number[right];
    } else if(nc2_kind[right]==2) {
        if(nc2_number[right]==1) rk=2;
        else if(nc2_number[right]==2 | nc2_number[right]==3) rk=3;
        else {nd_error=18;return 0;}
        r=nd_record(nc2_a[right],nc2_b[right],1);
        if(r<0) return 0;
    } else {nd_error=18;return 0;}
    return nd_add(68,l,r,(lk<<3)+rk+(is_unsigned<<6),number);
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
            r=nd_scalar(right);
            if(r<0) return 0;
            if(nd_add(18,0,r,0,0)==0) return 0;
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
    char op;
    if (rhs==0) { nd_error=19; return 0; }
    if (area==1) target_type=global_type[symbol];
    else target_type=local_type[symbol];
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
        if(nc2_kind[rhs]==8) {
            if(global_type[nc2_a[rhs]]==2)
                return nd_add(42,dst,0,0,0);
            if(global_type[nc2_a[rhs]]==1)
                return nd_add(48,dst,0,0,0);
            nd_error=25;return 0;
        }
        if(nc2_kind[rhs]==2) {
            if(nc2_number[rhs]==1) {
                src=nd_scalar(rhs);
                if(src<0) return 0;
                return nd_add(54,dst,src,0,0); /* zero-extend byte */
            }
            src=nd_word(rhs);
            if(src<0) return 0;
            return nd_add(28,dst,src,0,0);
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
        if(nc2_kind[expr]==8) {
            if(global_type[nc2_a[expr]]==2)
                return nd_add(43,0,0,0,0);
            if(global_type[nc2_a[expr]]==1)
                return nd_add(49,0,0,0,0);
            nd_error=21;return 0;
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
    if (nc2_kind[expr]==2) {
        if(nc2_number[expr]==1) src=nd_scalar(expr);
        else src=nd_word(expr); /* byte return truncates word */
        if (src<0) return 0;
        return nd_add(12,src,0,0,0);
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
    /* This first call tranche leaves ZP pointer save/restore for the
     * general calling-convention pass. Do not generate calls from
     * functions with live indirect array cursors until then. */
    if(nd_next_pointer!=0) {
        i=0;
        while(i<tb_count) {
            if(tb_op[i]==23) {nd_error=29;return 0;}
            i=i+1;
        }
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
