PIC_LD=ld

ARCHIVE_OBJS=
ARCHIVE_OBJS += _13837_archive_1.so
_13837_archive_1.so : archive.0/_13837_archive_1.a
	@$(AR) -s $<
	@$(PIC_LD) -shared  -Bsymbolic  -o .//../run/simv.daidir//_13837_archive_1.so --whole-archive $< --no-whole-archive
	@rm -f $@
	@ln -sf .//../run/simv.daidir//_13837_archive_1.so $@


ARCHIVE_OBJS += _13863_archive_1.so
_13863_archive_1.so : archive.0/_13863_archive_1.a
	@$(AR) -s $<
	@$(PIC_LD) -shared  -Bsymbolic  -o .//../run/simv.daidir//_13863_archive_1.so --whole-archive $< --no-whole-archive
	@rm -f $@
	@ln -sf .//../run/simv.daidir//_13863_archive_1.so $@


ARCHIVE_OBJS += _13864_archive_1.so
_13864_archive_1.so : archive.0/_13864_archive_1.a
	@$(AR) -s $<
	@$(PIC_LD) -shared  -Bsymbolic  -o .//../run/simv.daidir//_13864_archive_1.so --whole-archive $< --no-whole-archive
	@rm -f $@
	@ln -sf .//../run/simv.daidir//_13864_archive_1.so $@


ARCHIVE_OBJS += _13865_archive_1.so
_13865_archive_1.so : archive.0/_13865_archive_1.a
	@$(AR) -s $<
	@$(PIC_LD) -shared  -Bsymbolic  -o .//../run/simv.daidir//_13865_archive_1.so --whole-archive $< --no-whole-archive
	@rm -f $@
	@ln -sf .//../run/simv.daidir//_13865_archive_1.so $@


ARCHIVE_OBJS += _13866_archive_1.so
_13866_archive_1.so : archive.0/_13866_archive_1.a
	@$(AR) -s $<
	@$(PIC_LD) -shared  -Bsymbolic  -o .//../run/simv.daidir//_13866_archive_1.so --whole-archive $< --no-whole-archive
	@rm -f $@
	@ln -sf .//../run/simv.daidir//_13866_archive_1.so $@





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

