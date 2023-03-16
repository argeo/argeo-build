build-major=2
build-minor=3

# Required third party libraries
ECJ_BRANCH=4.26
BND_BRANCH=5.3
SYSLOGGER_BRANCH=$(build-major).$(build-minor)

find-build-tp:
	$(foreach base, $(A2_BASE), \
	$(eval LOGGER_JAR = $(shell if [ -f $(base)/org.argeo.tp/org.argeo.tp.syslogger.$(SYSLOGGER_BRANCH).jar ]; then echo $(base)/org.argeo.tp/org.argeo.tp.syslogger.$(SYSLOGGER_BRANCH).jar; fi)) \
	)
	echo $(LOGGER_JAR)