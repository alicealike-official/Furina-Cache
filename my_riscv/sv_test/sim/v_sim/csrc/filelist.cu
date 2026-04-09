PIC_LD=ld

ARCHIVE_OBJS=
ARCHIVE_OBJS += _26794_archive_1.so
_26794_archive_1.so : archive.0/_26794_archive_1.a
	@$(AR) -s $<
	@$(PIC_LD) -shared  -Bsymbolic  -o .//../simv.daidir//_26794_archive_1.so --whole-archive $< --no-whole-archive
	@rm -f $@
	@ln -sf .//../simv.daidir//_26794_archive_1.so $@


ARCHIVE_OBJS += _26838_archive_1.so
_26838_archive_1.so : archive.0/_26838_archive_1.a
	@$(AR) -s $<
	@$(PIC_LD) -shared  -Bsymbolic  -o .//../simv.daidir//_26838_archive_1.so --whole-archive $< --no-whole-archive
	@rm -f $@
	@ln -sf .//../simv.daidir//_26838_archive_1.so $@


ARCHIVE_OBJS += _26839_archive_1.so
_26839_archive_1.so : archive.0/_26839_archive_1.a
	@$(AR) -s $<
	@$(PIC_LD) -shared  -Bsymbolic  -o .//../simv.daidir//_26839_archive_1.so --whole-archive $< --no-whole-archive
	@rm -f $@
	@ln -sf .//../simv.daidir//_26839_archive_1.so $@


ARCHIVE_OBJS += _26840_archive_1.so
_26840_archive_1.so : archive.0/_26840_archive_1.a
	@$(AR) -s $<
	@$(PIC_LD) -shared  -Bsymbolic  -o .//../simv.daidir//_26840_archive_1.so --whole-archive $< --no-whole-archive
	@rm -f $@
	@ln -sf .//../simv.daidir//_26840_archive_1.so $@





O0_OBJS =

$(O0_OBJS) : %.o: %.c
	$(CC_CG) $(CFLAGS_O0) -c -o $@ $<
 

%.o: %.c
	$(CC_CG) $(CFLAGS_CG) -c -o $@ $<
CU_UDP_OBJS = \


CU_LVL_OBJS = \
SIM_l.o 

MAIN_OBJS = \
objs/amcQw_d.o 

CU_OBJS = $(MAIN_OBJS) $(ARCHIVE_OBJS) $(CU_UDP_OBJS) $(CU_LVL_OBJS)

