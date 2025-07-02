FROM flink:1.13.5-scala_2.12

# Remove the conflicting Hadoop JAR (adjust name if different)
RUN rm $FLINK_HOME/lib/flink-shaded-hadoop-2-uber-*.jar

# Add the correct Hadoop shaded JAR (download from Maven Central or your Flink distribution's /opt folder)
# Example: if you need Hadoop 3 compatibility
ARG HADOOP_SHADED_JAR_URL="https://repo.maven.apache.org/maven2/org/apache/flink/flink-shaded-hadoop3-uber/1.13.5/flink-shaded-hadoop3-uber-1.13.5.jar"
ADD ${HADOOP_SHADED_JAR_URL} $FLINK_HOME/lib/

# Copy your application JARs (if they are not already part of the base image setup)
# COPY /path/to/your/activity-aggregate-updater-1.0.0.jar $FLINK_HOME/lib/

# You might also need to ensure your application JAR doesn't bring in conflicting Hadoop deps.
# If the issue persists, inspect your application JAR's dependencies.
