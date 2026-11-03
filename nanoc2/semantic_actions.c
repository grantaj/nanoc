/*
 * nanoc2 semantic actions. These are called by the EXISTING nanoc1
 * expression and statement parsers, rather than reparsing C source.
 * Unsupported operations fail; no fall-through to the old emitter.
 */
char tf_mode;
char tf_symbol_count;
char tf_area[32], tf_slot[32], tf_function[32];
char tf_names[512];
char tf_ptr_count, tf_ptr_var[2], tf_scaled_event[32];
char tf_kind[32], tf_id[32], tf_index[32], tf_aux[32];
unsigned tf_num[32];
char tf_hexchars[17]="0123456789abcdef";

char tf_fail() { compiler_error=5; return 0; }
char *tb_name(char category,char number) {
    if(number==0 | number>=32) return tf_names;
    return tf_names + (unsigned)number*16;
}
char tb_char(char ch) { return io_write(output_handle,ch)==0; }

char tf_bind(char area,char slot) {
    char i;
    char *n;
    char fn;
    char p;
    fn=0;
    if(area==2) fn=current_func;
    i=1;
    while(i<=tf_symbol_count) {
        if(tf_area[i]==area & tf_slot[i]==slot & tf_function[i]==fn) return i;
        i=i+1;
    }
    if(tf_symbol_count>=30) {tf_fail();return 0;}
    i=tf_symbol_count+1;
    tf_symbol_count=i;
    tf_area[i]=area;tf_slot[i]=slot;tf_function[i]=fn;
    tf_scaled_event[i]=255;
    n=tb_name(1,i);
    p=0;n[p]='_';p=p+1;n[p]='_';p=p+1;
    if(area==1) {n[p]='g';p=p+1;}
    else {
        n[p]='v';p=p+1;
        n[p]=tf_hexchars[(fn>>4)&15];p=p+1;
        n[p]=tf_hexchars[fn&15];p=p+1;
        n[p]='_';p=p+1;
    }
    n[p]=tf_hexchars[(slot>>4)&15];p=p+1;
    n[p]=tf_hexchars[slot&15];p=p+1;n[p]=0;
    return i;
}
char tf_set(char k,char id,char index,unsigned n,char extra) {
    if(value_top>=32) return tf_fail();
    tf_kind[value_top]=k;tf_id[value_top]=id;
    tf_index[value_top]=index;tf_num[value_top]=n;
    tf_aux[value_top]=extra;
    return 1;
}
char tf_const(unsigned n) { return tf_set(2,0,0,n,0); }
char tf_variable(char area,char slot,char kind,char type) {
    char id;
    id=tf_bind(area,slot);
    if(id==0) return 0;
    if(kind==2) return tf_set(9,id,0,0,0);
    if(type==4) return tf_set(8,id,0,0,0);
    if(type!=1) return tf_fail();
    return tf_set(1,id,0,0,0);
}
char tf_pointer_slot(char id) {
    char p;
    p=0;
    while(p<tf_ptr_count) {
        if(tf_ptr_var[p]==id) return p;
        p=p+1;
    }
    if(tf_ptr_count>=2) {tf_fail();return 255;}
    p=tf_ptr_count;tf_ptr_count=p+1;tf_ptr_var[p]=id;
    return p;
}
char tf_indexed(char area,char slot,char kind,char type) {
    char id,k,idx,at,p;
    if(type!=1 | value_top==0) return tf_fail();
    id=tf_bind(area,slot);
    if(id==0) return 0;
    at=value_top-1;k=tf_kind[at];
    if(k==1) {
        idx=tf_id[at];
        if(kind==2) {tf_kind[at]=3;tf_id[at]=id;}
        else {
            p=tf_pointer_slot(id);
            if(p==255) return 0;
            tf_kind[at]=4;tf_id[at]=p;
        }
        tf_index[at]=idx;return 1;
    }
    if(k==6 & kind==2) {
        idx=tf_index[at];p=tf_id[at];
        if(tf_ptr_count!=0) return tf_fail();
        if(tf_scaled_event[p]==255) return tf_fail();
        if(tb_a[tf_scaled_event[p]]!=0 & tb_a[tf_scaled_event[p]]!=id) return tf_fail();
        tb_a[tf_scaled_event[p]]=id;
        tf_kind[at]=4;tf_id[at]=0;tf_index[at]=idx;
        return 1;
    }
    return tf_fail();
}
char tf_compare(char l,char r) {
    char k;
    k=tf_kind[l];
    if(k==3 | k==4) {
        if(k==3) {
            if(!tb_add(4,0,tf_id[l],tf_index[l],0)) return 0;
        } else {
            if(!tb_add(6,0,tf_id[l],tf_index[l],0)) return 0;
        }
        k=tf_kind[r];
        if(k==3) return tb_add(5,0,tf_id[r],tf_index[r],0);
        if(k==4) return tb_add(7,0,tf_id[r],tf_index[r],0);
        if(k==1) return tb_add(18,0,tf_id[r],0,0);
        if(k==2 & tf_num[r]<256) return tb_add(17,0,0,0,tf_num[r]);
    }
    if(k==1) {
        if(tf_kind[r]==1) return tb_add(9,tf_id[l],tf_id[r],0,0);
        if(tf_kind[r]==2 & tf_num[r]<256) return tb_add(8,tf_id[l],0,0,tf_num[r]);
    }
    return tf_fail();
}
char tf_binary(char op) {
    char l,r,inverse;
    unsigned stride;
    if(value_top<2) return tf_fail();
    l=value_top-2;r=value_top-1;
    if(op=='+' & tf_kind[l]==1 & tf_kind[r]==2 & tf_num[r]==1) {
        tf_kind[l]=10;return 1;
    }
    if(op=='+' & tf_kind[l]==1 & tf_kind[r]==1) {
        tf_kind[l]=6;tf_index[l]=tf_id[r];return 1;
    }
    if(op=='*' & tf_kind[l]==1 & tf_kind[r]==2) {
        stride=tf_num[r];
        if(stride==0 | stride>128 | (stride & (stride-1))!=0) return tf_fail();
        tf_kind[l]=5;tf_num[l]=stride;return 1;
    }
    inverse=0;
    if(op==142) inverse=2;
    if(op==143) inverse=1;
    if(op=='<') inverse=4;
    if(op==145) inverse=3;
    if(inverse==0) return tf_fail();
    if(tf_compare(l,r)==0) return 0;
    tf_kind[l]=7;tf_aux[l]=inverse;
    return 1;
}
char tf_assignment(char area,char slot,char type) {
    char dest,k;
    if(type!=1 & type!=2) return tf_fail();
    dest=tf_bind(area,slot);
    if(dest==0) return 0;
    k=tf_kind[0];
    if(k==2 & tf_num[0]<256) return tb_add(2,dest,0,0,tf_num[0]);
    if(k==10 & tf_id[0]==dest) return tb_add(3,dest,0,0,0);
    if(k==5 & type==2) {
        if(tf_ptr_count!=0) return tf_fail();
        tf_scaled_event[dest]=tb_count;
        return tb_add(14,0,0,tf_id[0],tf_num[0]);
    }
    return tf_fail();
}
char tf_false_jump(unsigned label) {
    if(tf_kind[0]!=7) return tf_fail();
    return tb_add(10,0,tf_aux[0],0,label);
}
char tf_return_value() {
    if(tf_kind[0]==2 & tf_num[0]<256)
        return tb_add(13,0,0,0,tf_num[0]);
    if(tf_kind[0]==1)
        return tb_add(12,tf_id[0],0,0,0);
    return tf_fail();
}
char tf_begin() {
    char i;
    tf_mode=1;tf_symbol_count=0;tf_ptr_count=0;
    tb_reset();
    i=0;
    while(i<32) {tf_scaled_event[i]=255;i=i+1;}
    return 1;
}
char tf_end() {
    unsigned i;
    char p;
    i=0;
    tf_mode=0;
    while(i<tb_count) {
        if(tb_op[i]==14 & tb_a[i]==0) return tf_fail();
        i=i+1;
    }
    p=0;
    while(p<tf_ptr_count) {
        if(tb_location("lda",1,tf_ptr_var[p],"")==0) return tf_fail();
        if(tb_text("\tsta __tptr")==0) return tf_fail();
        if(tb_hex2(p)==0) return tf_fail();
        if(tb_char(10)==0) return tf_fail();
        if(tb_location("lda",1,tf_ptr_var[p],"+1")==0) return tf_fail();
        if(tb_text("\tsta __tptr")==0) return tf_fail();
        if(tb_hex2(p)==0) return tf_fail();
        if(tb_text("+1\n")==0) return tf_fail();
        p=p+1;
    }
    if(tb_compile()==0) return tf_fail();
    return 1;
}
