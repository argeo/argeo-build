build-major=2
build-minor=3

# Required third party libraries
ECJ_BRANCH=4.26
BNDLIB_BRANCH=5.3
SYSLOGGER_BRANCH=$(build-major).$(build-minor)

#A2_BASE=/home/mbaudier/dev/git/unstable/output/a2 /home/mbaudier/dev/git/unstable/argeo-qa/build/argeo/output/a2 test

find-build-tp:
	$(lastword $(foreach base, $(A2_BASE), $(wildcard $(base)/org.argeo.tp/org.argeo.tp.syslogger.$(SYSLOGGER_BRANCH).jar)))
	##$(eval LOGGER_JAR = $(shell if [ -f $(base)/org.argeo.tp/org.argeo.tp.syslogger.$(SYSLOGGER_BRANCH).jar ]; then echo $(base)/org.argeo.tp/org.argeo.tp.syslogger.$(SYSLOGGER_BRANCH).jar; fi)) \
	#)
#	$(if $(wildcard $(candidate)), $(eval LOGGER_JAR = $(candidate))) \	
	echo $(LOGGER_JAR)