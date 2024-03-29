package org.argeo.build;

import static java.lang.System.Logger.Level.DEBUG;
import static java.lang.System.Logger.Level.ERROR;
import static java.lang.System.Logger.Level.INFO;
import static java.lang.System.Logger.Level.TRACE;
import static java.lang.System.Logger.Level.WARNING;
import static java.nio.file.FileVisitResult.CONTINUE;
import static java.nio.file.StandardOpenOption.APPEND;
import static java.nio.file.StandardOpenOption.CREATE;
import static java.util.jar.Attributes.Name.MANIFEST_VERSION;
import static org.argeo.build.Repackage.ManifestHeader.ARGEO_DO_NOT_MODIFY;
import static org.argeo.build.Repackage.ManifestHeader.ARGEO_ORIGIN_M2;
import static org.argeo.build.Repackage.ManifestHeader.ARGEO_ORIGIN_M2_MERGE;
import static org.argeo.build.Repackage.ManifestHeader.ARGEO_ORIGIN_M2_REPO;
import static org.argeo.build.Repackage.ManifestHeader.ARGEO_ORIGIN_NO_METADATA_GENERATION;
import static org.argeo.build.Repackage.ManifestHeader.ARGEO_ORIGIN_SOURCES_URI;
import static org.argeo.build.Repackage.ManifestHeader.ARGEO_ORIGIN_URI;
import static org.argeo.build.Repackage.ManifestHeader.AUTOMATIC_MODULE_NAME;
import static org.argeo.build.Repackage.ManifestHeader.BUNDLE_LICENSE;
import static org.argeo.build.Repackage.ManifestHeader.BUNDLE_SYMBOLICNAME;
import static org.argeo.build.Repackage.ManifestHeader.BUNDLE_VERSION;
import static org.argeo.build.Repackage.ManifestHeader.ECLIPSE_SOURCE_BUNDLE;
import static org.argeo.build.Repackage.ManifestHeader.EXPORT_PACKAGE;
import static org.argeo.build.Repackage.ManifestHeader.IMPORT_PACKAGE;
import static org.argeo.build.Repackage.ManifestHeader.REQUIRE_BUNDLE;
import static org.argeo.build.Repackage.ManifestHeader.SPDX_LICENSE_IDENTIFIER;

import java.io.BufferedWriter;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.lang.System.Logger;
import java.net.URI;
import java.net.URISyntaxException;
import java.nio.charset.StandardCharsets;
import java.nio.file.DirectoryStream;
import java.nio.file.FileSystem;
import java.nio.file.FileSystems;
import java.nio.file.FileVisitResult;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.PathMatcher;
import java.nio.file.Paths;
import java.nio.file.SimpleFileVisitor;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Properties;
import java.util.Set;
import java.util.StringJoiner;
import java.util.TreeMap;
import java.util.TreeSet;
import java.util.concurrent.CompletableFuture;
import java.util.jar.Attributes;
import java.util.jar.JarEntry;
import java.util.jar.JarInputStream;
import java.util.jar.JarOutputStream;
import java.util.jar.Manifest;
import java.util.zip.Deflater;

import aQute.bnd.osgi.Analyzer;
import aQute.bnd.osgi.Jar;

/** Repackages existing jar files into OSGi bundles in an A2 repository. */
public class Repackage {
	final static Logger logger = System.getLogger(Repackage.class.getName());

	/**
	 * Environment variable on whether sources should be packaged separately or
	 * integrated in the bundles.
	 */
	final static String ENV_SOURCE_BUNDLES = "SOURCE_BUNDLES";
	/** Environment variable on whether operations should be parallelised. */
	final static String ENV_ARGEO_BUILD_SEQUENTIAL = "ARGEO_BUILD_SEQUENTIAL";

	/** Whether repackaging should run in parallel (default) or sequentially. */
	final static boolean sequential = Boolean.parseBoolean(System.getenv(ENV_ARGEO_BUILD_SEQUENTIAL));

	/** Main entry point. */
	public static void main(String[] args) {
		if (sequential)
			logger.log(INFO, "Build will be sequential");
		if (args.length < 2) {
			System.err.println("Usage: <path to a2 output dir> <category1> <category2> ...");
			System.exit(1);
		}
		Path a2Base = Paths.get(args[0]).toAbsolutePath().normalize();
		Path descriptorsBase = Paths.get(".").toAbsolutePath().normalize();
		Repackage factory = new Repackage(a2Base, descriptorsBase);

		List<CompletableFuture<Void>> toDos = new ArrayList<>();
		for (int i = 1; i < args.length; i++) {
			Path categoryPath = Paths.get(args[i]);
			factory.cleanPreviousFailedBuild(categoryPath);
			if (sequential) // sequential processing happens here
				factory.processCategory(categoryPath);
			else
				toDos.add(CompletableFuture.runAsync(() -> factory.processCategory(categoryPath)));
		}
		if (!sequential)// parallel processing
			CompletableFuture.allOf(toDos.toArray(new CompletableFuture[toDos.size()])).join();

		// Summary
		StringBuilder sb = new StringBuilder();
		for (String licenseId : licensesUsed.keySet())
			for (String name : licensesUsed.get(licenseId))
				sb.append((licenseId.equals("") ? "Proprietary" : licenseId) + "\t\t" + name + "\n");
		logger.log(INFO, "# License summary:\n" + sb);
	}

	/** Deletes remaining sub directories. */
	void cleanPreviousFailedBuild(Path categoryPath) {
		Path outputCategoryPath = a2Base.resolve(categoryPath);
		if (!Files.exists(outputCategoryPath))
			return;
		// clean previous failed build
		try {
			for (Path subDir : Files.newDirectoryStream(outputCategoryPath, (d) -> Files.isDirectory(d))) {
				if (Files.exists(subDir)) {
					logger.log(WARNING, "Bundle dir " + subDir
							+ " already exists, probably from a previous failed build, deleting it...");
					deleteDirectory(subDir);
				}
			}
		} catch (IOException e) {
			logger.log(ERROR, "Cannot clean previous build", e);
		}
	}

	/** MANIFEST headers. */
	enum ManifestHeader {
		// OSGi
		/** OSGi bundle symbolic name. */
		BUNDLE_SYMBOLICNAME("Bundle-SymbolicName"), //
		/** OSGi bundle version. */
		BUNDLE_VERSION("Bundle-Version"), //
		/** OSGi bundle license. */
		BUNDLE_LICENSE("Bundle-License"), //
		/** OSGi exported packages list. */
		EXPORT_PACKAGE("Export-Package"), //
		/** OSGi imported packages list. */
		IMPORT_PACKAGE("Import-Package"), //
		/** OSGi required bundles. */
		REQUIRE_BUNDLE("Require-Bundle"), //
		/** OSGi path to embedded jar. */
		BUNDLE_CLASSPATH("Bundle-Classpath"), //
		// Java
		/** Java module name. */
		AUTOMATIC_MODULE_NAME("Automatic-Module-Name"), //
		// Eclipse
		/** Eclipse source bundle. */
		ECLIPSE_SOURCE_BUNDLE("Eclipse-SourceBundle"), //
		// SPDX
		/**
		 * SPDX license identifier.
		 * 
		 * @see https://spdx.org/licenses/
		 */
		SPDX_LICENSE_IDENTIFIER("SPDX-License-Identifier"), //
		// Argeo Origin
		/**
		 * Maven coordinates of the origin, possibly partial when using common.bnd or
		 * merge.bnd.
		 */
		ARGEO_ORIGIN_M2("Argeo-Origin-M2"), //
		/** List of Maven coordinates to merge. */
		ARGEO_ORIGIN_M2_MERGE("Argeo-Origin-M2-Merge"), //
		/** Maven repository, if not the default one. */
		ARGEO_ORIGIN_M2_REPO("Argeo-Origin-M2-Repo"), //
		/**
		 * Do not perform BND analysis of the origin component. Typically Import-Package
		 * and Export-Package will be kept untouched.
		 */
		ARGEO_ORIGIN_NO_METADATA_GENERATION("Argeo-Origin-NoMetadataGeneration"), //
//		/**
//		 * Embed the original jar without modifying it (may be required by some
//		 * proprietary licenses, such as JCR Day License).
//		 */
//		ARGEO_ORIGIN_EMBED("Argeo-Origin-Embed"), //
		/**
		 * Do not modify original jar (may be required by some proprietary licenses,
		 * such as JCR Day License).
		 */
		ARGEO_DO_NOT_MODIFY("Argeo-Origin-Do-Not-Modify"), //
		/**
		 * Origin (non-Maven) URI of the component. It may be anything (jar, archive,
		 * etc.).
		 */
		ARGEO_ORIGIN_URI("Argeo-Origin-URI"), //
		/**
		 * Origin (non-Maven) URI of the source of the component. It may be anything
		 * (jar, archive, code repository, etc.).
		 */
		ARGEO_ORIGIN_SOURCES_URI("Argeo-Origin-Sources-URI"), //
		;

		final String headerName;

		private ManifestHeader(String headerName) {
			this.headerName = headerName;
		}

		@Override
		public String toString() {
			return headerName;
		}

		/** Get the value from either a {@link Manifest} or a {@link Properties}. */
		String get(Object map) {
			if (map instanceof Manifest manifest)
				return manifest.getMainAttributes().getValue(headerName);
			else if (map instanceof Properties props)
				return props.getProperty(headerName);
			else
				throw new IllegalArgumentException("Unsupported mapping " + map.getClass());
		}

		/** Put the value into either a {@link Manifest} or a {@link Properties}. */
		void put(Object map, String value) {
			if (map instanceof Manifest manifest)
				manifest.getMainAttributes().putValue(headerName, value);
			else if (map instanceof Properties props)
				props.setProperty(headerName, value);
			else
				throw new IllegalArgumentException("Unsupported mapping " + map.getClass());
		}
	}

	/** Name of the file centralising information for multiple M2 artifacts. */
	final static String COMMON_BND = "common.bnd";
	/** Name of the file centralising information for mergin M2 artifacts. */
	final static String MERGE_BND = "merge.bnd";
	/**
	 * Subdirectory of the jar file where origin informations (changes, legal
	 * notices etc. are stored)
	 */
	final static String ARGEO_ORIGIN = "ARGEO-ORIGIN";
	/** File detailing modifications to the original component. */
	final static String CHANGES = ARGEO_ORIGIN + "/changes";
	/**
	 * Name of the file at the root of the repackaged jar, which prominently
	 * notifies that the component has be repackaged.
	 */
	final static String README_REPACKAGED = "README.repackaged";

	// cache
	/** Summary of all license seen during the repackaging. */
	final static Map<String, Set<String>> licensesUsed = new TreeMap<>();

	/** Directory where to download archives */
	final Path originBase;
	/** Directory where to download Maven artifacts */
	final Path mavenBase;

	/** A2 repository base for binary bundles */
	final Path a2Base;
	/** A2 repository base for source bundles */
	final Path a2SrcBase;
	/** A2 base for native components */
	final Path a2LibBase;
	/** Location of the descriptors driving the packaging */
	final Path descriptorsBase;
	/** URIs of archives to download */
	final Properties uris = new Properties();
	/** Mirrors for archive download. Key is URI prefix, value list of base URLs */
	final Map<String, List<String>> mirrors = new HashMap<String, List<String>>();

	/** Whether sources should be packaged separately */
	final boolean separateSources;

	/** Constructor initialises the various variables */
	public Repackage(Path a2Base, Path descriptorsBase) {
		separateSources = Boolean.parseBoolean(System.getenv(ENV_SOURCE_BUNDLES));
		if (separateSources)
			logger.log(INFO, "Sources will be packaged separately");

		Objects.requireNonNull(a2Base);
		Objects.requireNonNull(descriptorsBase);
		this.originBase = Paths.get(System.getProperty("user.home"), ".cache", "argeo/build/origin");
		this.mavenBase = Paths.get(System.getProperty("user.home"), ".m2", "repository");

		// TODO define and use a build base
		this.a2Base = a2Base;
		this.a2SrcBase = separateSources ? a2Base.getParent().resolve(a2Base.getFileName() + ".src") : a2Base;
		this.a2LibBase = a2Base.resolve("lib");
		this.descriptorsBase = descriptorsBase;
		if (!Files.exists(this.descriptorsBase))
			throw new IllegalArgumentException(this.descriptorsBase + " does not exist");

		// URIs mapping
		Path urisPath = this.descriptorsBase.resolve("uris.properties");
		if (Files.exists(urisPath)) {
			try (InputStream in = Files.newInputStream(urisPath)) {
				uris.load(in);
			} catch (IOException e) {
				throw new IllegalStateException("Cannot load " + urisPath, e);
			}
		}

		// Eclipse mirrors
		Path eclipseMirrorsPath = this.descriptorsBase.resolve("eclipse.mirrors.txt");
		List<String> eclipseMirrors = new ArrayList<>();
		if (Files.exists(eclipseMirrorsPath)) {
			try {
				eclipseMirrors = Files.readAllLines(eclipseMirrorsPath, StandardCharsets.UTF_8);
			} catch (IOException e) {
				throw new IllegalStateException("Cannot load " + eclipseMirrorsPath, e);
			}
			for (Iterator<String> it = eclipseMirrors.iterator(); it.hasNext();) {
				String value = it.next();
				if (value.strip().equals(""))
					it.remove();
			}
		}
		mirrors.put("http://www.eclipse.org/downloads", eclipseMirrors);
	}

	/*
	 * MAVEN ORIGIN
	 */
	/** Process a whole category/group id. */
	void processCategory(Path categoryRelativePath) {
		try {
			Path targetCategoryBase = descriptorsBase.resolve(categoryRelativePath);
			DirectoryStream<Path> bnds = Files.newDirectoryStream(targetCategoryBase,
					(p) -> p.getFileName().toString().endsWith(".bnd") && !p.getFileName().toString().equals(COMMON_BND)
							&& !p.getFileName().toString().equals(MERGE_BND));
			for (Path p : bnds) {
				processSingleM2ArtifactDistributionUnit(p);
			}

			DirectoryStream<Path> dus = Files.newDirectoryStream(targetCategoryBase, (p) -> Files.isDirectory(p));
			for (Path duDir : dus) {
				if (duDir.getFileName().toString().startsWith("eclipse-")) {
					processEclipseArchive(duDir);
				} else {
					processM2BasedDistributionUnit(duDir);
				}
			}
		} catch (IOException e) {
			throw new RuntimeException("Cannot process category " + categoryRelativePath, e);
		}
	}

	/** Process a standalone Maven artifact. */
	void processSingleM2ArtifactDistributionUnit(Path bndFile) {
		try {
			Path categoryRelativePath = descriptorsBase.relativize(bndFile.getParent());
			Path targetCategoryBase = a2Base.resolve(categoryRelativePath);

			Properties fileProps = new Properties();
			try (InputStream in = Files.newInputStream(bndFile)) {
				fileProps.load(in);
			}
			// use file name as symbolic name
			if (!fileProps.containsKey(BUNDLE_SYMBOLICNAME.toString())) {
				String symbolicName = bndFile.getFileName().toString();
				symbolicName = symbolicName.substring(0, symbolicName.length() - ".bnd".length());
				fileProps.put(BUNDLE_SYMBOLICNAME.toString(), symbolicName);
			}

			String m2Coordinates = fileProps.getProperty(ARGEO_ORIGIN_M2.toString());
			if (m2Coordinates == null)
				throw new IllegalArgumentException("No M2 coordinates available for " + bndFile);
			M2Artifact artifact = new M2Artifact(m2Coordinates);

			Path downloaded = downloadMaven(fileProps, artifact);

			boolean doNotModify = Boolean
					.parseBoolean(fileProps.getOrDefault(ARGEO_DO_NOT_MODIFY.toString(), "false").toString());
			if (doNotModify) {
				processNotModified(targetCategoryBase, downloaded, fileProps, artifact);
				return;
			}

			// regular processing
			A2Origin origin = new A2Origin();
			Path bundleDir = processBndJar(downloaded, targetCategoryBase, fileProps, artifact, origin);
			downloadAndProcessM2Sources(fileProps, artifact, bundleDir, false, false);
			createJar(bundleDir, origin);
		} catch (Exception e) {
			throw new RuntimeException("Cannot process " + bndFile, e);
		}
	}

	/**
	 * Process multiple Maven artifacts coming from a same project and therefore
	 * with information in common (typically the version), generating single bundles
	 * or merging them if necessary.
	 * 
	 * @see #COMMON_BND
	 * @see #MERGE_BND
	 */
	void processM2BasedDistributionUnit(Path duDir) {
		try {
			Path categoryRelativePath = descriptorsBase.relativize(duDir.getParent());
			Path targetCategoryBase = a2Base.resolve(categoryRelativePath);

			Path mergeBnd = duDir.resolve(MERGE_BND);
			if (Files.exists(mergeBnd)) // merge
				mergeM2Artifacts(mergeBnd);

			Path commonBnd = duDir.resolve(COMMON_BND);
			if (!Files.exists(commonBnd))
				return;

			Properties commonProps = new Properties();
			try (InputStream in = Files.newInputStream(commonBnd)) {
				commonProps.load(in);
			}

			String m2Version = commonProps.getProperty(ARGEO_ORIGIN_M2.toString());
			if (m2Version == null) {
				logger.log(WARNING, "Ignoring " + duDir + " as it is not an M2-based distribution unit");
				return;// ignore, this is probably an Eclipse archive
			}
			if (!m2Version.startsWith(":")) {
				throw new IllegalStateException("Only the M2 version can be specified: " + m2Version);
			}
			m2Version = m2Version.substring(1);

			DirectoryStream<Path> ds = Files.newDirectoryStream(duDir,
					(p) -> p.getFileName().toString().endsWith(".bnd") && !p.getFileName().toString().equals(COMMON_BND)
							&& !p.getFileName().toString().equals(MERGE_BND));
			for (Path p : ds) {
				Properties fileProps = new Properties();
				try (InputStream in = Files.newInputStream(p)) {
					fileProps.load(in);
				}
				String m2Coordinates = fileProps.getProperty(ARGEO_ORIGIN_M2.toString());
				M2Artifact artifact = new M2Artifact(m2Coordinates);
				if (artifact.getVersion() == null) {
					artifact.setVersion(m2Version);
				} else {
					logger.log(DEBUG, p.getFileName() + " : Using version " + artifact.getVersion()
							+ " specified in descriptor rather than " + m2Version + " specified in " + COMMON_BND);
				}

				// prepare manifest entries
				Properties mergedProps = new Properties();
				mergedProps.putAll(commonProps);

				fileEntries: for (Object key : fileProps.keySet()) {
					if (ARGEO_ORIGIN_M2.toString().equals(key))
						continue fileEntries;
					String value = fileProps.getProperty(key.toString());
					Object previousValue = mergedProps.put(key.toString(), value);
					if (previousValue != null) {
						logger.log(WARNING,
								commonBnd + ": " + key + " was " + previousValue + ", overridden with " + value);
					}
				}
				mergedProps.put(ARGEO_ORIGIN_M2.toString(), artifact.toM2Coordinates());
				if (!mergedProps.containsKey(BUNDLE_SYMBOLICNAME.toString())) {
					// use file name as symbolic name
					String symbolicName = p.getFileName().toString();
					symbolicName = symbolicName.substring(0, symbolicName.length() - ".bnd".length());
					mergedProps.put(BUNDLE_SYMBOLICNAME.toString(), symbolicName);
				}

				// download
				Path downloaded = downloadMaven(mergedProps, artifact);

				boolean doNotModify = Boolean
						.parseBoolean(mergedProps.getOrDefault(ARGEO_DO_NOT_MODIFY.toString(), "false").toString());
				if (doNotModify) {
					processNotModified(targetCategoryBase, downloaded, mergedProps, artifact);
				} else {
					A2Origin origin = new A2Origin();
					Path targetBundleDir = processBndJar(downloaded, targetCategoryBase, mergedProps, artifact, origin);
					downloadAndProcessM2Sources(mergedProps, artifact, targetBundleDir, false, false);
					createJar(targetBundleDir, origin);
				}
			}
		} catch (IOException e) {
			throw new RuntimeException("Cannot process " + duDir, e);
		}
	}

	/** Merge multiple Maven artifacts. */
	void mergeM2Artifacts(Path mergeBnd) throws IOException {
		Path duDir = mergeBnd.getParent();
		String category = duDir.getParent().getFileName().toString();
		Path targetCategoryBase = a2Base.resolve(category);

		Properties mergeProps = new Properties();
		// first, load common properties
		Path commonBnd = duDir.resolve(COMMON_BND);
		if (Files.exists(commonBnd))
			try (InputStream in = Files.newInputStream(commonBnd)) {
				mergeProps.load(in);
			}
		// then, the merge properties themselves
		try (InputStream in = Files.newInputStream(mergeBnd)) {
			mergeProps.load(in);
		}

		String m2Version = mergeProps.getProperty(ARGEO_ORIGIN_M2.toString());
		if (m2Version == null) {
			logger.log(WARNING, "Ignoring merging in " + duDir + " as it is not an M2-based distribution unit");
			return;// ignore, this is probably an Eclipse archive
		}
		if (!m2Version.startsWith(":")) {
			throw new IllegalStateException("Only the M2 version can be specified: " + m2Version);
		}
		m2Version = m2Version.substring(1);
		mergeProps.put(BUNDLE_VERSION.toString(), m2Version);

		String artifactsStr = mergeProps.getProperty(ARGEO_ORIGIN_M2_MERGE.toString());
		if (artifactsStr == null)
			throw new IllegalArgumentException(mergeBnd + ": " + ARGEO_ORIGIN_M2_MERGE + " must be set");

		String bundleSymbolicName = mergeProps.getProperty(BUNDLE_SYMBOLICNAME.toString());
		if (bundleSymbolicName == null)
			throw new IllegalArgumentException("Bundle-SymbolicName must be set in " + mergeBnd);
		CategoryNameVersion nameVersion = new M2Artifact(category + ":" + bundleSymbolicName + ":" + m2Version);

		A2Origin origin = new A2Origin();
		Path bundleDir = targetCategoryBase.resolve(bundleSymbolicName + "." + nameVersion.getBranch());

		StringJoiner originDesc = new StringJoiner(",");
		String[] artifacts = artifactsStr.split(",");
		artifacts: for (String str : artifacts) {
			String m2Coordinates = str.trim();
			if ("".equals(m2Coordinates))
				continue artifacts;
			M2Artifact artifact = new M2Artifact(m2Coordinates.trim());
			if (artifact.getVersion() == null)
				artifact.setVersion(m2Version);
			originDesc.add(artifact.toString());
			Path downloaded = downloadMaven(mergeProps, artifact);
			JarEntry entry;
			try (JarInputStream jarIn = new JarInputStream(Files.newInputStream(downloaded), false)) {
				entries: while ((entry = jarIn.getNextJarEntry()) != null) {
					if (entry.isDirectory())
						continue entries;
					if (entry.getName().endsWith(".RSA") || entry.getName().endsWith(".DSA")
							|| entry.getName().endsWith(".SF")) {
						origin.deleted.add("cryptographic signatures from " + artifact);
						continue entries;
					}
					if (entry.getName().endsWith("module-info.class")) { // skip Java 9 module info
						origin.deleted.add("Java module information (module-info.class) from " + artifact);
						continue entries;
					}
					if (entry.getName().startsWith("META-INF/versions/")) { // skip multi-version
						origin.deleted.add("additional Java versions (META-INF/versions) from " + artifact);
						continue entries;
					}
					if (entry.getName().startsWith("META-INF/maven/")) {
						origin.deleted.add("Maven information (META-INF/maven) from " + artifact);
						continue entries;
					}
					if (entry.getName().startsWith(".cache/")) { // Apache SSHD
						origin.deleted.add("cache directory (.cache) from " + artifact);
						continue entries;
					}
					if (entry.getName().equals("META-INF/DEPENDENCIES")) {
						origin.deleted.add("Dependencies (META-INF/DEPENDENCIES) from " + artifact);
						continue entries;
					}
					if (entry.getName().equals("META-INF/MANIFEST.MF")) {
						Path originalManifest = bundleDir.resolve(ARGEO_ORIGIN).resolve(artifact.getGroupId())
								.resolve(artifact.getArtifactId()).resolve("MANIFEST.MF");
						Files.createDirectories(originalManifest.getParent());
						try (OutputStream out = Files.newOutputStream(originalManifest)) {
							Files.copy(jarIn, originalManifest);
						}
						origin.added.add(
								"original MANIFEST (" + bundleDir.relativize(originalManifest) + ") from " + artifact);
						continue entries;
					}

					if (entry.getName().endsWith("NOTICE") || entry.getName().endsWith("NOTICE.txt")
							|| entry.getName().endsWith("NOTICE.md") || entry.getName().endsWith("LICENSE")
							|| entry.getName().endsWith("LICENSE.md") || entry.getName().endsWith("LICENSE-notice.md")
							|| entry.getName().endsWith("COPYING") || entry.getName().endsWith("COPYING.LESSER")) {
						Path artifactOriginDir = bundleDir.resolve(ARGEO_ORIGIN).resolve(artifact.getGroupId())
								.resolve(artifact.getArtifactId());
						Path target = artifactOriginDir.resolve(entry.getName());
						Files.createDirectories(target.getParent());
						Files.copy(jarIn, target);
						origin.moved.add(entry.getName() + " in " + artifact + " to " + bundleDir.relativize(target));
						continue entries;
					}
					Path target = bundleDir.resolve(entry.getName());
					Files.createDirectories(target.getParent());
					if (!Files.exists(target)) {
						Files.copy(jarIn, target);
					} else {
						if (entry.getName().startsWith("META-INF/services/")) {
							try (OutputStream out = Files.newOutputStream(target, StandardOpenOption.APPEND)) {
								out.write("\n".getBytes());
								jarIn.transferTo(out);
								logger.log(DEBUG, artifact.getArtifactId() + " - Appended " + entry.getName());
							}
							origin.modified.add(entry.getName() + ", merging from " + artifact);
						} else if (entry.getName().startsWith("org/apache/batik/")) {
							logger.log(TRACE, "Skip " + entry.getName());
							continue entries;
						} else if (entry.getName().startsWith("META-INF/NOTICE")) {
							logger.log(WARNING, "Skip " + entry.getName() + " from " + artifact);
							// TODO merge them?
							continue entries;
						} else {
							throw new IllegalStateException("File " + target + " from " + artifact + " already exists");
						}
					}
					logger.log(TRACE, () -> "Copied " + target);
				}
			}
			origin.added.add("binary content of " + artifact);

			// process sources
			downloadAndProcessM2Sources(mergeProps, artifact, bundleDir, true, false);
		}

		// additional service files
		Path servicesDir = duDir.resolve("services");
		if (Files.exists(servicesDir)) {
			for (Path p : Files.newDirectoryStream(servicesDir)) {
				Path target = bundleDir.resolve("META-INF/services/").resolve(p.getFileName());
				try (InputStream in = Files.newInputStream(p);
						OutputStream out = Files.newOutputStream(target, StandardOpenOption.APPEND);) {
					out.write("\n".getBytes());
					in.transferTo(out);
					logger.log(DEBUG, "Appended " + p);
				}
				origin.added.add(bundleDir.relativize(target).toString());
			}
		}

		// BND analysis
		Map<String, String> entries = new TreeMap<>();
		try (Analyzer bndAnalyzer = new Analyzer()) {
			bndAnalyzer.setProperties(mergeProps);
			Jar jar = new Jar(bundleDir.toFile());
			bndAnalyzer.setJar(jar);
			Manifest manifest = bndAnalyzer.calcManifest();

			keys: for (Object key : manifest.getMainAttributes().keySet()) {
				Object value = manifest.getMainAttributes().get(key);

				switch (key.toString()) {
				case "Tool":
				case "Bnd-LastModified":
				case "Created-By":
					continue keys;
				}
				if ("Require-Capability".equals(key.toString())
						&& value.toString().equals("osgi.ee;filter:=\"(&(osgi.ee=JavaSE)(version=1.1))\"")) {
					origin.deleted.add("MANIFEST header " + key);
					continue keys;// hack for very old classes
				}
				entries.put(key.toString(), value.toString());
			}
		} catch (Exception e) {
			throw new RuntimeException("Cannot process " + mergeBnd, e);
		}

		Manifest manifest = new Manifest();
		Path manifestPath = bundleDir.resolve("META-INF/MANIFEST.MF");
		Files.createDirectories(manifestPath.getParent());
		for (String key : entries.keySet()) {
			String value = entries.get(key);
			manifest.getMainAttributes().putValue(key, value);
		}
		manifest.getMainAttributes().putValue(ARGEO_ORIGIN_M2.toString(), originDesc.toString());

		processLicense(bundleDir, manifest);

		// write MANIFEST
		try (OutputStream out = Files.newOutputStream(manifestPath)) {
			manifest.write(out);
		}
		createJar(bundleDir, origin);
	}

	/** Generates MANIFEST using BND. */
	Path processBndJar(Path downloaded, Path targetCategoryBase, Properties fileProps, M2Artifact artifact,
			A2Origin origin) {
		try {
			Map<String, String> additionalEntries = new TreeMap<>();
			boolean doNotModifyManifest = Boolean.parseBoolean(
					fileProps.getOrDefault(ARGEO_ORIGIN_NO_METADATA_GENERATION.toString(), "false").toString());

			// Note: we always force the symbolic name
			if (doNotModifyManifest) {
				for (Object key : fileProps.keySet()) {
					String value = fileProps.getProperty(key.toString());
					additionalEntries.put(key.toString(), value);
				}
			} else {
				if (artifact != null) {
					if (!fileProps.containsKey(BUNDLE_SYMBOLICNAME.toString())) {
						fileProps.put(BUNDLE_SYMBOLICNAME.toString(), artifact.getName());
					}
					if (!fileProps.containsKey(BUNDLE_VERSION.toString())) {
						fileProps.put(BUNDLE_VERSION.toString(), artifact.getVersion());
					}
				}

				if (!fileProps.containsKey(EXPORT_PACKAGE.toString())) {
					fileProps.put(EXPORT_PACKAGE.toString(),
							"*;version=\"" + fileProps.getProperty(BUNDLE_VERSION.toString()) + "\"");
				}

				// BND analysis
				try (Analyzer bndAnalyzer = new Analyzer()) {
					bndAnalyzer.setProperties(fileProps);
					Jar jar = new Jar(downloaded.toFile());
					bndAnalyzer.setJar(jar);
					Manifest manifest = bndAnalyzer.calcManifest();

					keys: for (Object key : manifest.getMainAttributes().keySet()) {
						Object value = manifest.getMainAttributes().get(key);

						switch (key.toString()) {
						case "Tool":
						case "Bnd-LastModified":
						case "Created-By":
							continue keys;
						}
						if ("Require-Capability".equals(key.toString())
								&& value.toString().equals("osgi.ee;filter:=\"(&(osgi.ee=JavaSE)(version=1.1))\"")) {
							origin.deleted.add("MANIFEST header " + key);
							continue keys;// !! hack for very old classes
						}
						additionalEntries.put(key.toString(), value.toString());
					}
				}
			}
			Path targetBundleDir = processBundleJar(downloaded, targetCategoryBase, additionalEntries, origin);
			logger.log(DEBUG, () -> "Processed " + downloaded);
			return targetBundleDir;
		} catch (Exception e) {
			throw new RuntimeException("Cannot BND process " + downloaded, e);
		}

	}

	/** Process an artifact that should not be modified. */
	void processNotModified(Path targetCategoryBase, Path downloaded, Properties fileProps, M2Artifact artifact)
			throws IOException {
		// Some proprietary or signed artifacts do not allow any modification
		// When releasing (with separate sources), we just copy it
		Path unmodifiedTarget = targetCategoryBase
				.resolve(fileProps.getProperty(BUNDLE_SYMBOLICNAME.toString()) + "." + artifact.getBranch() + ".jar");
		Files.createDirectories(unmodifiedTarget.getParent());
		Files.copy(downloaded, unmodifiedTarget, StandardCopyOption.REPLACE_EXISTING);
		Path bundleDir = targetCategoryBase
				.resolve(fileProps.getProperty(BUNDLE_SYMBOLICNAME.toString()) + "." + artifact.getBranch());
		downloadAndProcessM2Sources(fileProps, artifact, bundleDir, false, true);
		Manifest manifest;
		try (JarInputStream jarIn = new JarInputStream(Files.newInputStream(unmodifiedTarget))) {
			manifest = jarIn.getManifest();
		}
		createSourceJar(bundleDir, manifest, fileProps);
	}

	/** Download and integrates sources for a single Maven artifact. */
	void downloadAndProcessM2Sources(Properties props, M2Artifact artifact, Path targetBundleDir, boolean merging,
			boolean unmodified) throws IOException {
		try {
			String repoStr = props.containsKey(ARGEO_ORIGIN_M2_REPO.toString())
					? props.getProperty(ARGEO_ORIGIN_M2_REPO.toString())
					: null;
			String alternateUri = props.getProperty(ARGEO_ORIGIN_SOURCES_URI.toString());
			M2Artifact sourcesArtifact = new M2Artifact(artifact.toM2Coordinates(), "sources");
			URI sourcesUrl = alternateUri != null ? new URI(alternateUri)
					: M2ConventionsUtils.mavenRepoUrl(repoStr, sourcesArtifact);
			Path sourcesDownloaded = downloadMaven(sourcesUrl, sourcesArtifact);
			processM2SourceJar(sourcesDownloaded, targetBundleDir, merging ? artifact : null, unmodified);
			logger.log(TRACE, () -> "Processed source " + sourcesDownloaded);
		} catch (Exception e) {
			logger.log(ERROR, () -> "Cannot download source for  " + artifact);
		}

	}

	/** Integrate sources from a downloaded jar file. */
	void processM2SourceJar(Path file, Path bundleDir, M2Artifact mergingFrom, boolean unmodified) throws IOException {
		A2Origin origin = new A2Origin();
		Path sourceDir = separateSources || unmodified ? bundleDir.getParent().resolve(bundleDir.toString() + ".src")
				: bundleDir.resolve("OSGI-OPT/src");
		try (JarInputStream jarIn = new JarInputStream(Files.newInputStream(file), false)) {

			String mergingMsg = "";
			if (mergingFrom != null)
				mergingMsg = " of " + mergingFrom;

			Files.createDirectories(sourceDir);
			JarEntry entry;
			entries: while ((entry = jarIn.getNextJarEntry()) != null) {
				String relPath = entry.getName();
				if (entry.isDirectory())
					continue entries;
				if (entry.getName().equals("META-INF/MANIFEST.MF")) {// skip META-INF entries
					origin.deleted.add("MANIFEST.MF from the sources" + mergingMsg);
					continue entries;
				}
				if (!unmodified) {
					if (entry.getName().startsWith("module-info.java")) {// skip Java module information
						origin.deleted.add("Java module information from the sources (module-info.java)" + mergingMsg);
						continue entries;
					}
					if (entry.getName().startsWith("/")) { // absolute paths
						int metaInfIndex = entry.getName().indexOf("META-INF");
						if (metaInfIndex >= 0) {
							relPath = entry.getName().substring(metaInfIndex);
							origin.moved.add(" to " + relPath + " entry with absolute path " + entry.getName());
						} else {
							logger.log(WARNING, entry.getName() + " has an absolute path");
							origin.deleted.add(entry.getName() + " from the sources" + mergingMsg);
						}
						continue entries;
					}
				}
				Path target = sourceDir.resolve(relPath);
				Files.createDirectories(target.getParent());
				if (!Files.exists(target)) {
					Files.copy(jarIn, target);
					logger.log(TRACE, () -> "Copied source " + target);
				} else {
					logger.log(TRACE, () -> target + " already exists, skipping...");
				}
			}
		}
		// write the changes
		if (separateSources || unmodified) {
			origin.appendChanges(sourceDir);
		} else {
			origin.added.add("source code under OSGI-OPT/src");
			origin.appendChanges(bundleDir);
		}
	}

	/** Download a Maven artifact. */
	Path downloadMaven(Properties props, M2Artifact artifact) throws IOException {
		String repoStr = props.containsKey(ARGEO_ORIGIN_M2_REPO.toString())
				? props.getProperty(ARGEO_ORIGIN_M2_REPO.toString())
				: null;
		String alternateUri = props.getProperty(ARGEO_ORIGIN_URI.toString());
		try {
			URI uri = alternateUri != null ? new URI(alternateUri) : M2ConventionsUtils.mavenRepoUrl(repoStr, artifact);
			return downloadMaven(uri, artifact);
		} catch (URISyntaxException e) {
			throw new IllegalArgumentException("Wrong aritfact URI", e);
		}
	}

	/** Download a Maven artifact. */
	Path downloadMaven(URI uri, M2Artifact artifact) throws IOException {
		return download(uri, mavenBase, M2ConventionsUtils.artifactPath("", artifact));
	}

	/*
	 * ECLIPSE ORIGIN
	 */
	/** Process an archive in Eclipse format. */
	void processEclipseArchive(Path duDir) {
		try {
			Path categoryRelativePath = descriptorsBase.relativize(duDir.getParent());
			Path targetCategoryBase = a2Base.resolve(categoryRelativePath);
			Files.createDirectories(targetCategoryBase);
			// first delete all directories from previous builds
			for (Path dir : Files.newDirectoryStream(targetCategoryBase, (p) -> Files.isDirectory(p)))
				deleteDirectory(dir);

			Files.createDirectories(originBase);

			Path commonBnd = duDir.resolve(COMMON_BND);
			Properties commonProps = new Properties();
			try (InputStream in = Files.newInputStream(commonBnd)) {
				commonProps.load(in);
			}
			String url = commonProps.getProperty(ARGEO_ORIGIN_URI.toString());
			if (url == null) {
				url = uris.getProperty(duDir.getFileName().toString());
				if (url == null)
					throw new IllegalStateException("No url available for " + duDir);
				commonProps.put(ARGEO_ORIGIN_URI.toString(), url);
			}
			Path downloaded = tryDownloadArchive(url, originBase);

			FileSystem zipFs = FileSystems.newFileSystem(downloaded, (ClassLoader) null);

			// filters
			List<PathMatcher> includeMatchers = new ArrayList<>();
			Properties includes = new Properties();
			try (InputStream in = Files.newInputStream(duDir.resolve("includes.properties"))) {
				includes.load(in);
			}
			for (Object pattern : includes.keySet()) {
				PathMatcher pathMatcher = zipFs.getPathMatcher("glob:/" + pattern);
				includeMatchers.add(pathMatcher);
			}

			List<PathMatcher> excludeMatchers = new ArrayList<>();
			Path excludeFile = duDir.resolve("excludes.properties");
			if (Files.exists(excludeFile)) {
				Properties excludes = new Properties();
				try (InputStream in = Files.newInputStream(excludeFile)) {
					excludes.load(in);
				}
				for (Object pattern : excludes.keySet()) {
					PathMatcher pathMatcher = zipFs.getPathMatcher("glob:/" + pattern);
					excludeMatchers.add(pathMatcher);
				}
			}

			// keys are the bundle directories
			Map<Path, A2Origin> origins = new HashMap<>();
			Files.walkFileTree(zipFs.getRootDirectories().iterator().next(), new SimpleFileVisitor<Path>() {

				@Override
				public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException {
					includeMatchers: for (PathMatcher includeMatcher : includeMatchers) {
						if (includeMatcher.matches(file)) {
							for (PathMatcher excludeMatcher : excludeMatchers) {
								if (excludeMatcher.matches(file)) {
									logger.log(TRACE, "Skipping excluded " + file);
									return FileVisitResult.CONTINUE;
								}
							}
							if (file.getFileName().toString().contains(".source_")) {
								processEclipseSourceJar(file, targetCategoryBase);
								logger.log(DEBUG, () -> "Processed source " + file);
							} else {
								Map<String, String> map = new HashMap<>();
								for (Object key : commonProps.keySet())
									map.put(key.toString(), commonProps.getProperty(key.toString()));
								A2Origin origin = new A2Origin();
								Path bundleDir = processBundleJar(file, targetCategoryBase, map, origin);
								if (bundleDir == null) {
									logger.log(WARNING, "No bundle dir created for " + file + ", skipping...");
									return FileVisitResult.CONTINUE;
								}
								origins.put(bundleDir, origin);
								logger.log(DEBUG, () -> "Processed " + file);
							}
							break includeMatchers;
						}
					}
					return FileVisitResult.CONTINUE;
				}
			});

			DirectoryStream<Path> dirs = Files.newDirectoryStream(targetCategoryBase, (p) -> Files.isDirectory(p)
					&& p.getFileName().toString().indexOf('.') >= 0 && !p.getFileName().toString().endsWith(".src"));
			for (Path bundleDir : dirs) {
				A2Origin origin = origins.get(bundleDir);
				Objects.requireNonNull(origin, "No A2 origin found for " + bundleDir);
				createJar(bundleDir, origin);
			}
		} catch (IOException e) {
			throw new RuntimeException("Cannot process " + duDir, e);
		}

	}

	/** Process sources in Eclipse format. */
	void processEclipseSourceJar(Path file, Path targetBase) throws IOException {
		try {
			A2Origin origin = new A2Origin();
			Path bundleDir;
			try (JarInputStream jarIn = new JarInputStream(Files.newInputStream(file), false)) {
				Manifest manifest = jarIn.getManifest();

				String[] relatedBundle = manifest.getMainAttributes().getValue(ECLIPSE_SOURCE_BUNDLE.toString())
						.split(";");
				String version = relatedBundle[1].substring("version=\"".length());
				version = version.substring(0, version.length() - 1);
				NameVersion nameVersion = new NameVersion(relatedBundle[0], version);
				bundleDir = targetBase.resolve(nameVersion.getName() + "." + nameVersion.getBranch());

				Path sourceDir = separateSources ? bundleDir.getParent().resolve(bundleDir.toString() + ".src")
						: bundleDir.resolve("OSGI-OPT/src");

				Files.createDirectories(sourceDir);
				JarEntry entry;
				entries: while ((entry = jarIn.getNextJarEntry()) != null) {
					if (entry.isDirectory())
						continue entries;
					if (entry.getName().startsWith("META-INF"))// skip META-INF entries
						continue entries;
					Path target = sourceDir.resolve(entry.getName());
					Files.createDirectories(target.getParent());
					Files.copy(jarIn, target);
					logger.log(TRACE, () -> "Copied source " + target);
				}

				// write the changes
				if (separateSources) {
					origin.appendChanges(sourceDir);
				} else {
					origin.added.add("source code under OSGI-OPT/src");
					origin.appendChanges(bundleDir);
				}
			}
		} catch (IOException e) {
			throw new IllegalStateException("Cannot process " + file, e);
		}
	}

	/*
	 * COMMON PROCESSING
	 */
	/** Normalise a single (that is, non-merged) bundle. */
	Path processBundleJar(Path file, Path targetBase, Map<String, String> entries, A2Origin origin) throws IOException {
//		boolean embed = Boolean.parseBoolean(entries.getOrDefault(ARGEO_ORIGIN_EMBED.toString(), "false").toString());
		boolean doNotModify = Boolean
				.parseBoolean(entries.getOrDefault(ManifestHeader.ARGEO_DO_NOT_MODIFY.toString(), "false").toString());
		NameVersion nameVersion;
		Path bundleDir;
		// singleton
		boolean isSingleton = false;
		Manifest manifest;
		Manifest sourceManifest;
		try (JarInputStream jarIn = new JarInputStream(Files.newInputStream(file), false)) {
			sourceManifest = jarIn.getManifest();
			if (sourceManifest == null)
				logger.log(WARNING, file + " has no manifest");
			manifest = sourceManifest != null ? new Manifest(sourceManifest) : new Manifest();

			String rawSourceSymbolicName = manifest.getMainAttributes().getValue(BUNDLE_SYMBOLICNAME.toString());
			if (rawSourceSymbolicName != null) {
				// make sure there is no directive
				String[] arr = rawSourceSymbolicName.split(";");
				for (int i = 1; i < arr.length; i++) {
					if (arr[i].trim().equals("singleton:=true"))
						isSingleton = true;
					logger.log(DEBUG, file.getFileName() + " is a singleton");
				}
			}
			// remove problematic entries in MANIFEST
			manifest.getEntries().clear();

			String ourSymbolicName = entries.get(BUNDLE_SYMBOLICNAME.toString());
			String ourVersion = entries.get(BUNDLE_VERSION.toString());

			if (ourSymbolicName != null && ourVersion != null) {
				nameVersion = new NameVersion(ourSymbolicName, ourVersion);
			} else {
				nameVersion = nameVersionFromManifest(manifest);
				if (nameVersion == null)
					throw new IllegalStateException("Could not compute name/version from Manifest");
				if (ourVersion != null && !nameVersion.getVersion().equals(ourVersion)) {
					logger.log(WARNING,
							"Original version is " + nameVersion.getVersion() + " while new version is " + ourVersion);
					entries.put(BUNDLE_VERSION.toString(), ourVersion);
				}
				if (ourSymbolicName != null) {
					// we always force our symbolic name
					nameVersion.setName(ourSymbolicName);
				}
			}

			bundleDir = targetBase.resolve(nameVersion.getName() + "." + nameVersion.getBranch());

			// copy original MANIFEST
			if (sourceManifest != null) {
				Path originalManifest = bundleDir.resolve(ARGEO_ORIGIN).resolve("MANIFEST.MF");
				Files.createDirectories(originalManifest.getParent());
				try (OutputStream out = Files.newOutputStream(originalManifest)) {
					sourceManifest.write(out);
				}
				origin.moved.add("original MANIFEST to " + bundleDir.relativize(originalManifest));
			}

			// force Java 9 module name
			entries.put(ManifestHeader.AUTOMATIC_MODULE_NAME.toString(), nameVersion.getName());

			boolean isNative = false;
			String os = null;
			String arch = null;
			if (bundleDir.startsWith(a2LibBase)) {
				isNative = true;
				Path libRelativePath = a2LibBase.relativize(bundleDir);
				os = libRelativePath.getName(0).toString();
				arch = libRelativePath.getName(1).toString();
			}

			// copy entries
			JarEntry entry;
			entries: while ((entry = jarIn.getNextJarEntry()) != null) {
				if (entry.isDirectory())
					continue entries;
				if (!doNotModify) {
					if (entry.getName().endsWith(".RSA") || entry.getName().endsWith(".DSA")
							|| entry.getName().endsWith(".SF")) {
						origin.deleted.add("cryptographic signatures");
						continue entries;
					}
					if (entry.getName().endsWith("module-info.class")) { // skip Java 9 module info
						origin.deleted.add("Java module information (module-info.class)");
						continue entries;
					}
					if (entry.getName().startsWith("META-INF/versions/")) { // skip multi-version
						origin.deleted.add("additional Java versions (META-INF/versions)");
						continue entries;
					}
					if (entry.getName().startsWith("META-INF/maven/")) {
						origin.deleted.add("Maven information (META-INF/maven)");
						continue entries;
					}
					// skip file system providers as they cause issues with native image
					if (entry.getName().startsWith("META-INF/services/java.nio.file.spi.FileSystemProvider")) {
						origin.deleted
								.add("file system providers (META-INF/services/java.nio.file.spi.FileSystemProvider)");
						continue entries;
					}
				}
				if (entry.getName().startsWith("OSGI-OPT/src/")) { // skip embedded sources
					origin.deleted.add("embedded sources");
					continue entries;
				}
				Path target = bundleDir.resolve(entry.getName());
				Files.createDirectories(target.getParent());
				Files.copy(jarIn, target);

				// native libraries
				boolean removeDllFromJar = true;
				if (isNative && (entry.getName().endsWith(".so") || entry.getName().endsWith(".dll")
						|| entry.getName().endsWith(".jnilib") || entry.getName().endsWith(".a"))) {
					Path categoryDir = bundleDir.getParent();
					boolean copyDll = false;
					Path targetDll = categoryDir.resolve(bundleDir.relativize(target));
					if (nameVersion.getName().equals("com.sun.jna")) {
						if (arch.equals("x86_64"))
							arch = "x86-64";
						if (os.equals("macosx"))
							os = "darwin";
						if (target.getParent().getFileName().toString().equals(os + "-" + arch)) {
							copyDll = true;
						}
						targetDll = categoryDir.resolve(target.getFileName());
					} else {
						copyDll = true;
					}
					if (copyDll) {
						Files.createDirectories(targetDll.getParent());
						if (Files.exists(targetDll))
							Files.delete(targetDll);
						Files.copy(target, targetDll);
					}

					if (removeDllFromJar) {
						Files.delete(target);
						origin.deleted.add(bundleDir.relativize(target).toString());
					}
				}
				logger.log(TRACE, () -> "Copied " + target);
			}
		}

		// copy MANIFEST
		Path manifestPath = bundleDir.resolve("META-INF/MANIFEST.MF");
		Files.createDirectories(manifestPath.getParent());

		if (isSingleton && entries.containsKey(BUNDLE_SYMBOLICNAME.toString())) {
			entries.put(BUNDLE_SYMBOLICNAME.toString(),
					entries.get(BUNDLE_SYMBOLICNAME.toString()) + ";singleton:=true");
		}

		// Final MANIFEST decisions
		// We also check the original OSGi metadata and compare with our changes
		for (String key : entries.keySet()) {
			String value = entries.get(key);
			String previousValue = manifest.getMainAttributes().getValue(key);
			boolean wasDifferent = previousValue != null && !previousValue.equals(value);
			boolean keepPrevious = false;
			if (wasDifferent) {
				if (SPDX_LICENSE_IDENTIFIER.toString().equals(key) && previousValue != null)
					keepPrevious = true;
				else if (BUNDLE_VERSION.toString().equals(key) && wasDifferent)
					if (previousValue.equals(value + ".0")) // typically a Maven first release
						keepPrevious = true;

				if (keepPrevious) {
					if (logger.isLoggable(DEBUG))
						logger.log(DEBUG, file.getFileName() + ": " + key + " was NOT modified, value kept is "
								+ previousValue + ", not overriden with " + value);
					value = previousValue;
				}
			}

			manifest.getMainAttributes().putValue(key, value);
			if (wasDifferent && !keepPrevious) {
				if (IMPORT_PACKAGE.toString().equals(key) || EXPORT_PACKAGE.toString().equals(key))
					logger.log(TRACE, () -> file.getFileName() + ": " + key + " was modified");
				else if (BUNDLE_SYMBOLICNAME.toString().equals(key) || AUTOMATIC_MODULE_NAME.toString().equals(key))
					logger.log(DEBUG,
							file.getFileName() + ": " + key + " was " + previousValue + ", overridden with " + value);
				else
					logger.log(WARNING,
							file.getFileName() + ": " + key + " was " + previousValue + ", overridden with " + value);
				origin.modified.add("MANIFEST header " + key);
			}

			// !! hack to remove unresolvable
			if (key.equals("Provide-Capability") || key.equals("Require-Capability"))
				if (nameVersion.getName().equals("osgi.core") || nameVersion.getName().equals("osgi.cmpn")) {
					manifest.getMainAttributes().remove(key);
					origin.deleted.add("MANIFEST header " + key);
				}
		}

		// de-pollute MANIFEST
		for (Iterator<Map.Entry<Object, Object>> manifestEntries = manifest.getMainAttributes().entrySet()
				.iterator(); manifestEntries.hasNext();) {
			Map.Entry<Object, Object> manifestEntry = manifestEntries.next();
			String key = manifestEntry.getKey().toString();
			// TODO make it more generic
			if (key.equals(REQUIRE_BUNDLE.toString()) && nameVersion.getName().equals("com.sun.jna.platform"))
				manifestEntries.remove();
			switch (key) {
			case "Archiver-Version":
			case "Build-By":
			case "Created-By":
			case "Originally-Created-By":
			case "Tool":
			case "Bnd-LastModified":
				manifestEntries.remove();
				origin.deleted.add("MANIFEST header " + manifestEntry.getKey());
				break;
			default:
				if (sourceManifest != null && !sourceManifest.getMainAttributes().containsKey(manifestEntry.getKey()))
					origin.added.add("MANIFEST header " + manifestEntry.getKey());
			}
		}

		processLicense(bundleDir, manifest);

		origin.modified.add("MANIFEST (META-INF/MANIFEST.MF)");
		// write the MANIFEST
		try (OutputStream out = Files.newOutputStream(manifestPath)) {
			manifest.write(out);
		}
		return bundleDir;
	}

	/** Process SPDX license identifier. */
	void processLicense(Path bundleDir, Manifest manifest) {
		String spdxLicenceId = manifest.getMainAttributes().getValue(SPDX_LICENSE_IDENTIFIER.toString());
		String bundleLicense = manifest.getMainAttributes().getValue(BUNDLE_LICENSE.toString());
		if (spdxLicenceId == null) {
			logger.log(ERROR, bundleDir.getFileName() + ": " + SPDX_LICENSE_IDENTIFIER + " not available, "
					+ BUNDLE_LICENSE + " is " + bundleLicense);
		} else {
			// only use the first licensing option
			int orIndex = spdxLicenceId.indexOf(" OR ");
			if (orIndex >= 0)
				spdxLicenceId = spdxLicenceId.substring(0, orIndex).trim();

			String bundleDirName = bundleDir.getFileName().toString();
			// force licenses of some well-known components
			// even if we say otherwise (typically because from an Eclipse archive)
			if (bundleDirName.startsWith("org.apache."))
				spdxLicenceId = "Apache-2.0";
			if (bundleDirName.startsWith("com.sun.jna."))
				spdxLicenceId = "Apache-2.0";
			if (bundleDirName.startsWith("com.ibm.icu."))
				spdxLicenceId = "ICU";
			if (bundleDirName.startsWith("javax.annotation."))
				spdxLicenceId = "GPL-2.0-only WITH Classpath-exception-2.0";
			if (bundleDirName.startsWith("javax.inject."))
				spdxLicenceId = "Apache-2.0";
			if (bundleDirName.startsWith("org.osgi."))
				spdxLicenceId = "Apache-2.0";

			manifest.getMainAttributes().putValue(SPDX_LICENSE_IDENTIFIER.toString(), spdxLicenceId);
			if (!licensesUsed.containsKey(spdxLicenceId))
				licensesUsed.put(spdxLicenceId, new TreeSet<>());
			licensesUsed.get(spdxLicenceId).add(bundleDir.getParent().getFileName() + "/" + bundleDir.getFileName());
		}
	}

	/*
	 * UTILITIES
	 */
	/** Recursively deletes a directory. */
	static void deleteDirectory(Path path) throws IOException {
		if (!Files.exists(path))
			return;
		Files.walkFileTree(path, new SimpleFileVisitor<Path>() {
			@Override
			public FileVisitResult postVisitDirectory(Path directory, IOException e) throws IOException {
				if (e != null)
					throw e;
				Files.delete(directory);
				return CONTINUE;
			}

			@Override
			public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException {
				Files.delete(file);
				return CONTINUE;
			}
		});
	}

	/** Extract name/version from a MANIFEST. */
	NameVersion nameVersionFromManifest(Manifest manifest) {
		Attributes attrs = manifest.getMainAttributes();
		// symbolic name
		String symbolicName = attrs.getValue(ManifestHeader.BUNDLE_SYMBOLICNAME.toString());
		if (symbolicName == null)
			return null;
		// make sure there is no directive
		symbolicName = symbolicName.split(";")[0];

		String version = attrs.getValue(ManifestHeader.BUNDLE_VERSION.toString());
		return new NameVersion(symbolicName, version);
	}

	/** Try to download from an URI. */
	Path tryDownloadArchive(String uriStr, Path dir) throws IOException {
		// find mirror
		List<String> urlBases = null;
		String uriPrefix = null;
		uriPrefixes: for (String uriPref : mirrors.keySet()) {
			if (uriStr.startsWith(uriPref)) {
				if (mirrors.get(uriPref).size() > 0) {
					urlBases = mirrors.get(uriPref);
					uriPrefix = uriPref;
					break uriPrefixes;
				}
			}
		}
		if (urlBases == null)
			try {
				return downloadArchive(new URI(uriStr), dir);
			} catch (FileNotFoundException | URISyntaxException e) {
				throw new FileNotFoundException("Cannot find " + uriStr);
			}

		// try to download
		for (String urlBase : urlBases) {
			String relativePath = uriStr.substring(uriPrefix.length());
			String uStr = urlBase + relativePath;
			try {
				return downloadArchive(new URI(uStr), dir);
			} catch (FileNotFoundException | URISyntaxException e) {
				logger.log(WARNING, "Cannot download " + uStr + ", trying another mirror");
			}
		}
		throw new FileNotFoundException("Cannot find " + uriStr);
	}

	/**
	 * Effectively download an archive.
	 */
	Path downloadArchive(URI uri, Path dir) throws IOException {
		return download(uri, dir, (String) null);
	}

	/**
	 * Effectively download. Synchronised in order to avoid downloading twice in
	 * parallel.
	 */
	synchronized Path download(URI uri, Path dir, String name) throws IOException {

		Path dest;
		if (name == null) {
			// We use also use parent directory in case the archive itself has a fixed name
			String[] segments = uri.getPath().split("/");
			name = segments.length > 1 ? segments[segments.length - 2] + '-' + segments[segments.length - 1]
					: segments[segments.length - 1];
		}

		dest = dir.resolve(name);
		if (Files.exists(dest)) {
			logger.log(TRACE, () -> "File " + dest + " already exists for " + uri + ", not downloading again");
			return dest;
		} else {
			Files.createDirectories(dest.getParent());
		}

		try (InputStream in = uri.toURL().openStream()) {
			Files.copy(in, dest);
			logger.log(DEBUG, () -> "Downloaded " + dest + " from " + uri);
		}
		return dest;
	}

	/** Create a JAR file from a directory. */
	Path createJar(Path bundleDir, A2Origin origin) throws IOException {
		Path manifestPath = bundleDir.resolve("META-INF/MANIFEST.MF");
		Manifest manifest;
		try (InputStream in = Files.newInputStream(manifestPath)) {
			manifest = new Manifest(in);
		}
		// legal requirements
		origin.appendChanges(bundleDir);
		createReadMe(bundleDir, manifest);

		// create the jar
		Path jarPath = bundleDir.getParent().resolve(bundleDir.getFileName() + ".jar");
		try (JarOutputStream jarOut = new JarOutputStream(Files.newOutputStream(jarPath), manifest)) {
			jarOut.setLevel(Deflater.DEFAULT_COMPRESSION);
			Files.walkFileTree(bundleDir, new SimpleFileVisitor<Path>() {

				@Override
				public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException {
					if (file.getFileName().toString().equals("MANIFEST.MF"))
						return super.visitFile(file, attrs);
					JarEntry entry = new JarEntry(
							bundleDir.relativize(file).toString().replace(File.separatorChar, '/'));
					jarOut.putNextEntry(entry);
					Files.copy(file, jarOut);
					return super.visitFile(file, attrs);
				}

			});
		}
		deleteDirectory(bundleDir);

		if (separateSources)
			createSourceJar(bundleDir, manifest, null);

		return jarPath;
	}

	/** Package sources separately, in the Eclipse-SourceBundle format. */
	void createSourceJar(Path bundleDir, Manifest manifest, Properties props) throws IOException {
		boolean unmodified = props != null;
		Path bundleCategoryDir = bundleDir.getParent();
		Path sourceDir = bundleCategoryDir.resolve(bundleDir.toString() + ".src");
		if (!Files.exists(sourceDir)) {
			logger.log(WARNING, sourceDir + " does not exist, skipping...");
			return;
		}

		Path relPath = a2Base.relativize(bundleCategoryDir);
		Path srcCategoryDir = a2SrcBase.resolve(relPath);
		Path srcJarP = srcCategoryDir.resolve(sourceDir.getFileName() + ".jar");
		Files.createDirectories(srcJarP.getParent());

		String bundleSymbolicName = manifest.getMainAttributes().getValue("Bundle-SymbolicName").toString();
		// in case there are additional directives
		bundleSymbolicName = bundleSymbolicName.split(";")[0];
		Manifest srcManifest = new Manifest();
		srcManifest.getMainAttributes().put(MANIFEST_VERSION, "1.0");
		BUNDLE_SYMBOLICNAME.put(srcManifest, bundleSymbolicName + ".src");
		BUNDLE_VERSION.put(srcManifest, BUNDLE_VERSION.get(manifest));
		ECLIPSE_SOURCE_BUNDLE.put(srcManifest,
				bundleSymbolicName + ";version=\"" + BUNDLE_VERSION.get(manifest) + "\"");

		// metadata
		createReadMe(sourceDir, unmodified ? props : manifest);
		// create jar
		try (JarOutputStream srcJarOut = new JarOutputStream(Files.newOutputStream(srcJarP), srcManifest)) {
			// srcJarOut.setLevel(Deflater.BEST_COMPRESSION);
			Files.walkFileTree(sourceDir, new SimpleFileVisitor<Path>() {

				@Override
				public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException {
					if (file.getFileName().toString().equals("MANIFEST.MF"))
						return super.visitFile(file, attrs);
					JarEntry entry = new JarEntry(
							sourceDir.relativize(file).toString().replace(File.separatorChar, '/'));
					srcJarOut.putNextEntry(entry);
					Files.copy(file, srcJarOut);
					return super.visitFile(file, attrs);
				}

			});
		}
		deleteDirectory(sourceDir);
	}

	/**
	 * Generate a readme clarifying and prominently notifying of the repackaging and
	 * modifications.
	 */
	void createReadMe(Path jarDir, Object mapping) throws IOException {
		// write repackaged README
		try (BufferedWriter writer = Files.newBufferedWriter(jarDir.resolve(README_REPACKAGED))) {
			boolean merged = ARGEO_ORIGIN_M2_MERGE.get(mapping) != null;
			if (merged)
				writer.append("This component is a merging of third party components"
						+ " in order to comply with A2 packaging standards.\n");
			else
				writer.append("This component is a repackaging of a third party component"
						+ " in order to comply with A2 packaging standards.\n");

			// license
			String spdxLicenseId = SPDX_LICENSE_IDENTIFIER.get(mapping);
			if (spdxLicenseId == null)
				throw new IllegalStateException("An SPDX license id must have beend defined at this stage.");
			writer.append("\nIt is redistributed under the following license:\n\n");
			writer.append("SPDX-Identifier: " + spdxLicenseId + "\n\n");

			if (!spdxLicenseId.startsWith("LicenseRef")) {// standard
				int withIndex = spdxLicenseId.indexOf(" WITH ");
				if (withIndex >= 0) {
					String simpleId = spdxLicenseId.substring(0, withIndex).trim();
					String exception = spdxLicenseId.substring(withIndex + " WITH ".length());
					writer.append("which are available here: https://spdx.org/licenses/" + simpleId
							+ "\nand here: https://spdx.org/licenses/" + exception + "\n");
				} else {
					writer.append("which is available here: https://spdx.org/licenses/" + spdxLicenseId + "\n");
				}
			} else {
				String url = BUNDLE_LICENSE.get(mapping);
				if (url != null) {
					writer.write("which is available here: " + url + "\n");
				} else {
					logger.log(ERROR, "No licence URL for " + jarDir);
				}
			}

			// origin
			String originDesc = ARGEO_ORIGIN_URI.get(mapping);
			if (originDesc != null)
				writer.append("\nThe original component comes from " + originDesc + ".\n");
			else {
				String m2Repo = ARGEO_ORIGIN_M2_REPO.get(mapping);
				originDesc = ARGEO_ORIGIN_M2.get(mapping);
				if (originDesc != null)
					writer.append("\nThe original component has M2 coordinates:\n" + originDesc.replace(',', '\n')
							+ "\n" + (m2Repo != null ? "\nin M2 repository " + m2Repo + "\n" : ""));
				else
					logger.log(ERROR, "Cannot find origin information in " + jarDir);
			}
			String originSources = ARGEO_ORIGIN_SOURCES_URI.get(mapping);
			if (originSources != null)
				writer.append("\nThe original sources come from " + originSources + ".\n");

			if (Files.exists(jarDir.resolve(CHANGES)))
				writer.append("\nA detailed list of changes is available under " + CHANGES + ".\n");

			if (!jarDir.getFileName().toString().endsWith(".src")) {// binary archive
				if (separateSources)
					writer.append("Corresponding sources are available in the related archive named "
							+ jarDir.toString() + ".src.jar.\n");
				else
					writer.append("Corresponding sources are available under OSGI-OPT/src.\n");
			}
		}
	}

	/**
	 * Gathers modifications performed on the original binaries and sources,
	 * especially in order to comply with their license requirements.
	 */
	class A2Origin {
		A2Origin() {

		}

		Set<String> modified = new TreeSet<>();
		Set<String> deleted = new TreeSet<>();
		Set<String> added = new TreeSet<>();
		Set<String> moved = new TreeSet<>();

		/** Append changes to the A2-ORIGIN/changes file. */
		void appendChanges(Path baseDirectory) throws IOException {
			if (modified.isEmpty() && deleted.isEmpty() && added.isEmpty() && moved.isEmpty())
				return; // no changes
			Path changesFile = baseDirectory.resolve(CHANGES);
			Files.createDirectories(changesFile.getParent());
			try (BufferedWriter writer = Files.newBufferedWriter(changesFile, APPEND, CREATE)) {
				for (String msg : added)
					writer.write("- Added " + msg + ".\n");
				for (String msg : modified)
					writer.write("- Modified " + msg + ".\n");
				for (String msg : moved)
					writer.write("- Moved " + msg + ".\n");
				for (String msg : deleted)
					writer.write("- Deleted " + msg + ".\n");
			}
		}
	}
}

/** Simple representation of an M2 artifact. */
class M2Artifact extends CategoryNameVersion {
	private String classifier;

	M2Artifact(String m2coordinates) {
		this(m2coordinates, null);
	}

	M2Artifact(String m2coordinates, String classifier) {
		String[] parts = m2coordinates.split(":");
		setCategory(parts[0]);
		setName(parts[1]);
		if (parts.length > 2) {
			setVersion(parts[2]);
		}
		this.classifier = classifier;
	}

	String getGroupId() {
		return super.getCategory();
	}

	String getArtifactId() {
		return super.getName();
	}

	String toM2Coordinates() {
		return getCategory() + ":" + getName() + (getVersion() != null ? ":" + getVersion() : "");
	}

	String getClassifier() {
		return classifier != null ? classifier : "";
	}

	String getExtension() {
		return "jar";
	}
}

/** Utilities around Maven (conventions based). */
class M2ConventionsUtils {
	final static String MAVEN_CENTRAL_BASE_URL = "https://repo1.maven.org/maven2/";

	/** The file name of this artifact when stored */
	static String artifactFileName(M2Artifact artifact) {
		return artifact.getArtifactId() + '-' + artifact.getVersion()
				+ (artifact.getClassifier().equals("") ? "" : '-' + artifact.getClassifier()) + '.'
				+ artifact.getExtension();
	}

	/** Absolute path to the file */
	static String artifactPath(String artifactBasePath, M2Artifact artifact) {
		return artifactParentPath(artifactBasePath, artifact) + '/' + artifactFileName(artifact);
	}

	/** Absolute path to the file */
	static String artifactUrl(String repoUrl, M2Artifact artifact) {
		if (repoUrl.endsWith("/"))
			return repoUrl + artifactPath("/", artifact).substring(1);
		else
			return repoUrl + artifactPath("/", artifact);
	}

	/** Absolute path to the file */
	static URI mavenRepoUrl(String repoBase, M2Artifact artifact) throws URISyntaxException {
		String uri = artifactUrl(repoBase == null ? MAVEN_CENTRAL_BASE_URL : repoBase, artifact);
		return new URI(uri);
	}

	/** Absolute path to the directories where the files will be stored */
	static String artifactParentPath(String artifactBasePath, M2Artifact artifact) {
		return artifactBasePath + (artifactBasePath.endsWith("/") || artifactBasePath.equals("") ? "" : "/")
				+ artifactParentPath(artifact);
	}

	/** Relative path to the directories where the files will be stored */
	static String artifactParentPath(M2Artifact artifact) {
		return artifact.getGroupId().replace('.', '/') + '/' + artifact.getArtifactId() + '/' + artifact.getVersion();
	}

	/** Singleton */
	private M2ConventionsUtils() {
	}
}

/** Combination of a category, a name and a version. */
class CategoryNameVersion extends NameVersion {
	private String category;

	CategoryNameVersion() {
	}

	CategoryNameVersion(String category, String name, String version) {
		super(name, version);
		this.category = category;
	}

	CategoryNameVersion(String category, NameVersion nameVersion) {
		super(nameVersion);
		this.category = category;
	}

	String getCategory() {
		return category;
	}

	void setCategory(String category) {
		this.category = category;
	}

	@Override
	public String toString() {
		return category + ":" + super.toString();
	}

}

/** Combination of a name and a version. */
class NameVersion implements Comparable<NameVersion> {
	private String name;
	private String version;

	NameVersion() {
	}

	/** Interprets string in OSGi-like format my.module.name;version=0.0.0 */
	NameVersion(String nameVersion) {
		int index = nameVersion.indexOf(";version=");
		if (index < 0) {
			setName(nameVersion);
			setVersion(null);
		} else {
			setName(nameVersion.substring(0, index));
			setVersion(nameVersion.substring(index + ";version=".length()));
		}
	}

	NameVersion(String name, String version) {
		this.name = name;
		this.version = version;
	}

	NameVersion(NameVersion nameVersion) {
		this.name = nameVersion.getName();
		this.version = nameVersion.getVersion();
	}

	String getName() {
		return name;
	}

	void setName(String name) {
		this.name = name;
	}

	String getVersion() {
		return version;
	}

	void setVersion(String version) {
		this.version = version;
	}

	String getBranch() {
		String[] parts = getVersion().split("\\.");
		if (parts.length < 2)
			throw new IllegalStateException("Version " + getVersion() + " cannot be interpreted as branch.");
		return parts[0] + "." + parts[1];
	}

	@Override
	public boolean equals(Object obj) {
		if (obj instanceof NameVersion) {
			NameVersion nameVersion = (NameVersion) obj;
			return name.equals(nameVersion.getName()) && version.equals(nameVersion.getVersion());
		} else
			return false;
	}

	@Override
	public int hashCode() {
		return name.hashCode();
	}

	@Override
	public String toString() {
		return name + ":" + version;
	}

	public int compareTo(NameVersion o) {
		if (o.getName().equals(name))
			return version.compareTo(o.getVersion());
		else
			return name.compareTo(o.getName());
	}
}
