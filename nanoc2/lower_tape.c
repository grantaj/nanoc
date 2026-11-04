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

/* Calls are effects in the existing statement-event order. The first
 * supported ABI case is one byte argument/byte result. The callee's static
 * argument home is identified by its original parser symbol number.
 */
char nd_call(unsigned node, char callee)
{
    unsigned argument;
    int value;
    if(node==0 | nc2_kind[node]!=8 | nc2_a[node]!=callee |
       nc2_b[node]!=1) {nd_error=28;return 0;}
    argument=nc2_left[node];
    if(argument==0) {nd_error=28;return 0;}
    if(nc2_kind[argument]==1) {
        if(nc2_number[argument]>255) {nd_error=28;return 0;}
        if(nd_add(21,0,0,0,nc2_number[argument])==0) return 0;
    } else if(nc2_kind[argument]==2) {
        value=nd_scalar(argument);
        if(value<0) return 0;
        if(nd_add(15,0,value,0,0)==0) return 0;
    } else if(nc2_kind[argument]==4 | nc2_kind[argument]==5) {
        if(nd_index(argument,0)==0) return 0;
    } else {nd_error=28;return 0;}
    if(nd_add(22,callee,0,0,0)==0) return 0; /* STA callee arg */
    return nd_add(23,callee,0,0,0);          /* JSR + return state */
}

char nd_condition(unsigned expr, unsigned exit_label)
{
    unsigned left;
    unsigned right;
    char op;
    char rel;
    int l;
    int r;
    if (expr==0) { nd_error=16; return 0; }
    if (nc2_kind[expr]==2) {
        l=nd_scalar(expr);
        if (l<0) return 0;
        if (nd_add(8,l,0,0,0)==0) return 0;
        return nd_add(10,0,1,0,exit_label);
    }
    if (nc2_kind[expr]!=6) { nd_error=16; return 0; }
    op=nc2_a[expr];
    if (op==142) rel=2;       /* ==: false when NE */
    else if (op==143) rel=1;  /* !=: false when EQ */
    else if (op=='<') rel=4;  /* <: false when carry set */
    else if (op==145) rel=3;  /* >=: false when carry clear */
    else { nd_error=17; return 0; }
    left=nc2_left[expr];right=nc2_right[expr];
    if (nc2_kind[left]==2) {
        l=nd_scalar(left);
        if (l<0) return 0;
        if (nc2_kind[right]==2) {
            r=nd_scalar(right);
            if (r<0) return 0;
            if (nd_add(9,l,r,0,0)==0) return 0;
        } else if (nc2_kind[right]==1) {
            if (nc2_number[right]>255) { nd_error=18; return 0; }
            if (nd_add(8,l,0,0,nc2_number[right])==0) return 0;
        } else { nd_error=18; return 0; }
    } else if (nc2_kind[left]==4 | nc2_kind[left]==5) {
        if (nd_index(left,0)==0) return 0;
        if (nc2_kind[right]==4 | nc2_kind[right]==5) {
            if (nd_index(right,1)==0) return 0;
        } else if (nc2_kind[right]==2) {
            r=nd_scalar(right);
            if (r<0) return 0;
            if (nd_add(18,0,r,0,0)==0) return 0;
        } else if (nc2_kind[right]==1) {
            if (nc2_number[right]>255) { nd_error=18; return 0; }
            if (nd_add(17,0,0,0,nc2_number[right])==0) return 0;
        } else { nd_error=18; return 0; }
    } else { nd_error=18; return 0; }
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
    if (target_type!=1) { nd_error=25; return 0; }
    dst=nd_record(area,symbol,1);
    if (dst<0) return 0;
    if (nc2_kind[rhs]==1) {
        if (nc2_number[rhs]>255) { nd_error=20; return 0; }
        return nd_add(2,dst,0,0,nc2_number[rhs]);
    }
    if (nc2_kind[rhs]==2) {
        src=nd_scalar(rhs);
        if (src<0) return 0;
        if (nd_add(15,0,src,0,0)==0) return 0;
        return nd_add(16,dst,0,0,0);
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
    if (expr==0) { nd_error=21; return 0; }
    if (nc2_kind[expr]==1) {
        if (nc2_number[expr]>255) { nd_error=21; return 0; }
        return nd_add(13,0,0,0,nc2_number[expr]);
    }
    if (nc2_kind[expr]==2) {
        src=nd_scalar(expr);
        if (src<0) return 0;
        return nd_add(12,src,0,0,0);
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
    if (nc2_return_type!=1) { nd_error=26; return 0; }
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
