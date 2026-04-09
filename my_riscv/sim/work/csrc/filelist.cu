PIC_LD=ld

ARCHIVE_OBJS=
ARCHIVE_OBJS += _15741_archive_1.so
_15741_archive_1.so : archive.0/_15741_archive_1.a
	@$(AR) -s $<
	@$(PIC_LD) -shared  -Bsymbolic  -o .//../run/simv.daidir//_15741_archive_1.so --whole-archive $< --no-whole-archive
	@rm -f $@
	@ln -sf .//../run/simv.daidir//_15741_archive_1.so $@


ARCHIVE_OBJS += _15767_archive_1.so
_15767_archive_1.so : archive.0/_15767_archive_1.a
	@$(AR) -s $<
	@$(PIC_LD) -shared  -Bsymbolic  -o .//../run/simv.daidir//_15767_archive_1.so --whole-archive $< --no-whole-archive
	@rm -f $@
	@ln -sf .//../run/simv.daidir//_15767_archive_1.so $@


ARCHIVE_OBJS += _15768_archive_1.so
_15768_archive_1.so : archive.0/_15768_archive_1.a
	@$(AR) -s $<
	@$(PIC_LD) -shared  -Bsymbolic  -o .//../run/simv.daidir//_15768_archive_1.so --whole-archive $< --no-whole-archive
	@rm -f $@
	@ln -sf .//../run/simv.daidir//_15768_archive_1.so $@


ARCHIVE_OBJS += _15769_archive_1.so
_15769_archive_1.so : archive.0/_15769_archive_1.a
	@$(AR) -s $<
	@$(PIC_LD) -shared  -Bsymbolic  -o .//../run/simv.daidir//_15769_archive_1.so --whole-archive $< --no-whole-archive
	@rm -f $@
	@ln -sf .//../run/simv.daidir//_15769_archive_1.so $@


ARCHIVE_OBJS += _15770_archive_1.so
_15770_archive_1.so : archive.0/_15770_archive_1.a
	@$(AR) -s $<
	@$(PIC_LD) -shared  -Bsymbolic  -o .//../run/simv.daidir//_15770_archive_1.so --whole-archive $< --no-whole-archive
	@rm -f $@
	@ln -sf .//../run/simv.daidir//_15770_archive_1.so $@





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

