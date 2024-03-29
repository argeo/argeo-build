package org.argeo.build;

import static java.lang.System.Logger.Level.DEBUG;
import static java.lang.System.Logger.Level.ERROR;
import static java.lang.System.Logger.Level.INFO;
import static java.lang.System.Logger.Level.WARNING;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.PrintWriter;
import java.lang.System.Logger;
import java.lang.System.Logger.Level;
import java.lang.management.ManagementFactory;
import java.nio.file.DirectoryStream;
import java.nio.file.FileVisitResult;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.PathMatcher;
import java.nio.file.Paths;
import java.nio.file.SimpleFileVisitor;
import java.nio.file.StandardCopyOption;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Properties;
import java.util.StringJoiner;
import java.util.StringTokenizer;
import java.util.TreeMap;
import java.util.concurrent.CompletableFuture;
import java.util.jar.Attributes;
import java.util.jar.JarEntry;
import java.util.jar.JarOutputStream;
import java.util.jar.Manifest;
import java.util.stream.Collectors;
import java.util.zip.Deflater;

import org.eclipse.jdt.core.compiler.CompilationProgress;

import aQute.bnd.osgi.Analyzer;
import aQute.bnd.osgi.Jar;

/**
 * Minimalistic OSGi compiler and packager, meant to be used as a single file
 * without being itself compiled first. It depends on the Eclipse batch compiler
 * (aka. ECJ) and the BND Libs library for OSGi metadata generation (which
 * itselfs depends on slf4j).<br/>
 * <br/>
 * For example, a typical system call would be:<br/>
 * <code>java -cp "/path/to/ECJ jar:/path/to/bndlib jar:/path/to/SLF4J jar" /path/to/cloned/argeo-build/src/org/argeo/build/Make.java action --option1 argument1 argument2 --option2 argument3 </code>
 */
public class Make {
	private final static Logger logger = System.getLogger(Make.class.getName());

	/**
	 * Environment variable on whether sources should be packaged separately or
	 * integrated in the bundles.
	 */
	private final static String ENV_SOURCE_BUNDLES = "SOURCE_BUNDLES";

	/**
	 * Environment variable on whether legal files at the root of the sources should
	 * be included in the generated bundles. Should be set to true when building
	 * third-party software in order no to include the build harness license into
	 * the generated bundles.
	 */
	private final static String ENV_NO_SDK_LEGAL = "NO_SDK_LEGAL";

	/**
	 * Environment variable to override the default location for the Argeo Build
	 * configuration files. Typically used if Argeo Build has been compiled and
	 * packaged separately.
	 */
	private final static String ENV_ARGEO_BUILD_CONFIG = "ARGEO_BUILD_CONFIG";

	/** Make file variable (in {@link #SDK_MK}) with a path to the sources base. */
	private final static String VAR_SDK_SRC_BASE = "SDK_SRC_BASE";

	/**
	 * Make file variable (in {@link #SDK_MK}) with a path to the build output base.
	 */
	private final static String VAR_SDK_BUILD_BASE = "SDK_BUILD_BASE";
	/**
	 * Make file variable (in {@link #BRANCH_MK}) with the branch.
	 */
	private final static String VAR_BRANCH = "BRANCH";

	/** Name of the local-specific Makefile (sdk.mk). */
	final static String SDK_MK = "sdk.mk";
	/** Name of the branch definition Makefile (branch.mk). */
	final static String BRANCH_MK = "branch.mk";

	/** The execution directory (${user.dir}). */
	final Path execDirectory;
	/** Base of the source code, typically the cloned git repository. */
	final Path sdkSrcBase;
	/**
	 * The base of the builder, typically a submodule pointing to the INCLUDEpublic
	 * argeo-build directory.
	 */
	final Path argeoBuildBase;
	/** The base of the build for all layers. */
	final Path sdkBuildBase;
	/** The base of the build for this layer. */
	final Path buildBase;
	/** The base of the a2 output for all layers. */
	final Path a2Output;
	/** The base of the a2 sources when packaged separately. */
	final Path a2srcOutput;

	/** Whether sources should be packaged separately. */
	final boolean sourceBundles;
	/** Whether common legal files should be included. */
	final boolean noSdkLegal;

	/** Constructor initialises the base directories. */
	public Make() throws IOException {
		sourceBundles = Boolean.parseBoolean(System.getenv(ENV_SOURCE_BUNDLES));
		if (sourceBundles)
			logger.log(Level.INFO, "Sources will be packaged separately");
		noSdkLegal = Boolean.parseBoolean(System.getenv(ENV_NO_SDK_LEGAL));
		if (noSdkLegal)
			logger.log(Level.INFO, "SDK legal files will NOT be included");

		execDirectory = Paths.get(System.getProperty("user.dir"));
		Path sdkMkP = findSdkMk(execDirectory);
		Objects.requireNonNull(sdkMkP, "No " + SDK_MK + " found under " + execDirectory);

		Map<String, String> context = readMakefileVariables(sdkMkP);
		sdkSrcBase = Paths.get(context.computeIfAbsent(VAR_SDK_SRC_BASE, (key) -> {
			throw new IllegalStateException(key + " not found");
		})).toAbsolutePath();

		Path argeoBuildBaseT = sdkSrcBase.resolve("sdk/argeo-build");
		if (!Files.exists(argeoBuildBaseT)) {
			String fromEnv = System.getenv(ENV_ARGEO_BUILD_CONFIG);
			if (fromEnv != null)
				argeoBuildBaseT = Paths.get(fromEnv);
			if (fromEnv == null || !Files.exists(argeoBuildBaseT)) {
				throw new IllegalStateException(
						"Argeo Build not found. Did you initialise the git submodules or set the "
								+ ENV_ARGEO_BUILD_CONFIG + " environment variable?");
			}
		}
		argeoBuildBase = argeoBuildBaseT;

		sdkBuildBase = Paths.get(context.computeIfAbsent(VAR_SDK_BUILD_BASE, (key) -> {
			throw new IllegalStateException(key + " not found");
		})).toAbsolutePath();
		buildBase = sdkBuildBase.resolve(sdkSrcBase.getFileName());
		a2Output = sdkBuildBase.resolve("a2");
		a2srcOutput = sdkBuildBase.resolve("a2.src");
	}

	/*
	 * ACTIONS
	 */
	/** Compile and create the bundles in one go. */
	void all(Map<String, List<String>> options) throws IOException {
		compile(options);
		bundle(options);
	}

	/** Compile all the bundles which have been passed via the --bundle argument. */
	void compile(Map<String, List<String>> options) throws IOException {
		List<String> bundles = options.get("--bundles");
		Objects.requireNonNull(bundles, "--bundles argument must be set");
		if (bundles.isEmpty())
			return;

		List<String> a2Categories = options.getOrDefault("--dep-categories", new ArrayList<>());
		List<String> a2Bases = options.getOrDefault("--a2-bases", new ArrayList<>());
		a2Bases = a2Bases.stream().distinct().collect(Collectors.toList());// remove duplicates
		if (a2Bases.isEmpty() || !a2Bases.contains(a2Output.toString())) {// make sure a2 output is available
			a2Bases.add(a2Output.toString());
		}

		List<String> compilerArgs = new ArrayList<>();

		Path ecjArgs = argeoBuildBase.resolve("ecj.args");
		compilerArgs.add("@" + ecjArgs);

		// classpath
		if (!a2Categories.isEmpty()) {
			// We will keep only the highest major.minor
			// and order by bundle name, for predictability
			Map<String, A2Jar> a2Jars = new TreeMap<>();

//			StringJoiner modulePath = new StringJoiner(File.pathSeparator);
			for (String a2Base : a2Bases) {
				categories: for (String a2Category : a2Categories) {
					Path a2Dir = Paths.get(a2Base).resolve(a2Category);
					if (!Files.exists(a2Dir))
						continue categories;
//					modulePath.add(a2Dir.toString());
					for (Path jarP : Files.newDirectoryStream(a2Dir, (p) -> p.getFileName().toString().endsWith(".jar")
							&& !p.getFileName().toString().endsWith(".src.jar"))) {
						A2Jar a2Jar = new A2Jar(jarP);
						if (a2Jars.containsKey(a2Jar.name)) {
							A2Jar current = a2Jars.get(a2Jar.name);
							if (a2Jar.major > current.major)
								a2Jars.put(a2Jar.name, a2Jar);
							else if (a2Jar.major == current.major && a2Jar.minor > current.minor)
								a2Jars.put(a2Jar.name, a2Jar);
							// keep if minor equals
						} else {
							a2Jars.put(a2Jar.name, a2Jar);
						}
					}
				}
			}

			StringJoiner classPath = new StringJoiner(File.pathSeparator);
			for (Iterator<A2Jar> it = a2Jars.values().iterator(); it.hasNext();)
				classPath.add(it.next().path.toString());

			compilerArgs.add("-cp");
			compilerArgs.add(classPath.toString());
//			compilerArgs.add("--module-path");
//			compilerArgs.add(modulePath.toString());
		}

		// sources
		boolean atLeastOneBundleToCompile = false;
		bundles: for (String bundle : bundles) {
			StringBuilder sb = new StringBuilder();
			Path bundlePath = execDirectory.resolve(bundle);
			if (!Files.exists(bundlePath)) {
				if (bundles.size() == 1) {
					logger.log(WARNING, "Bundle " + bundle + " not found in " + execDirectory
							+ ", assuming this is this directory, as only one bundle was requested.");
					bundlePath = execDirectory;
				} else
					throw new IllegalArgumentException("Bundle " + bundle + " not found in " + execDirectory);
			}
			Path bundleSrc = bundlePath.resolve("src");
			if (!Files.exists(bundleSrc)) {
				logger.log(WARNING, bundleSrc + " does not exist, skipping it, as this is not a Java bundle");
				continue bundles;
			}
			sb.append(bundleSrc);
			sb.append("[-d");
			compilerArgs.add(sb.toString());
			sb = new StringBuilder();
			sb.append(buildBase.resolve(bundle).resolve("bin"));
			sb.append("]");
			compilerArgs.add(sb.toString());
			atLeastOneBundleToCompile = true;
		}

		if (!atLeastOneBundleToCompile)
			return;

		if (logger.isLoggable(INFO))
			compilerArgs.add("-time");

		if (logger.isLoggable(DEBUG)) {
			logger.log(DEBUG, "Compiler arguments:");
			for (String arg : compilerArgs)
				logger.log(DEBUG, arg);
		}

		boolean success = org.eclipse.jdt.core.compiler.batch.BatchCompiler.compile(
				compilerArgs.toArray(new String[compilerArgs.size()]), new PrintWriter(System.out),
				new PrintWriter(System.err), new MakeCompilationProgress());
		if (!success) // kill the process if compilation failed
			throw new IllegalStateException("Compilation failed");
	}

	/** Package the bundles. */
	void bundle(Map<String, List<String>> options) throws IOException {
		// check arguments
		List<String> bundles = options.get("--bundles");
		Objects.requireNonNull(bundles, "--bundles argument must be set");
		if (bundles.isEmpty())
			return;

		List<String> categories = options.get("--category");
		Objects.requireNonNull(categories, "--category argument must be set");
		if (categories.size() != 1)
			throw new IllegalArgumentException("One and only one --category must be specified");
		String category = categories.get(0);

		final String branch;
		Path branchMk = sdkSrcBase.resolve(BRANCH_MK);
		if (Files.exists(branchMk)) {
			Map<String, String> branchVariables = readMakefileVariables(branchMk);
			branch = branchVariables.get(VAR_BRANCH);
		} else {
			branch = null;
		}

		long begin = System.currentTimeMillis();
		// create jars in parallel
		List<CompletableFuture<Void>> toDos = new ArrayList<>();
		for (String bundle : bundles) {
			toDos.add(CompletableFuture.runAsync(() -> {
				try {
					createBundle(branch, bundle, category);
				} catch (IOException e) {
					throw new RuntimeException("Packaging of " + bundle + " failed", e);
				}
			}));
		}
		CompletableFuture.allOf(toDos.toArray(new CompletableFuture[toDos.size()])).join();
		long duration = System.currentTimeMillis() - begin;
		logger.log(DEBUG, "Packaging took " + duration + " ms");
	}

	/** Install or uninstall bundles and native output. */
	void install(Map<String, List<String>> options, boolean uninstall) throws IOException {
		final String LIB_ = "lib/";
		final String NATIVE_ = "native/";

		// check arguments
		List<String> bundles = multiArg(options, "--bundles", true);
		if (bundles.isEmpty())
			return;
		String category = singleArg(options, "--category", true);
		Path targetA2 = Paths.get(singleArg(options, "--target", true));
		String nativeTargetArg = singleArg(options, "--target-native", false);
		Path nativeTargetA2 = nativeTargetArg != null ? Paths.get(nativeTargetArg) : null;
		String targetOs = singleArg(options, "--os", nativeTargetArg != null);
		logger.log(INFO, (uninstall ? "Uninstalling bundles from " : "Installing bundles to ") + targetA2);

		final String branch;
		Path branchMk = sdkSrcBase.resolve(BRANCH_MK);
		if (Files.exists(branchMk)) {
			Map<String, String> branchVariables = readMakefileVariables(branchMk);
			branch = branchVariables.get(VAR_BRANCH);
		} else {
			throw new IllegalArgumentException(VAR_BRANCH + " variable must be set.");
		}

		Properties properties = new Properties();
		Path branchBnd = sdkSrcBase.resolve("sdk/branches/" + branch + ".bnd");
		if (Files.exists(branchBnd))
			try (InputStream in = Files.newInputStream(branchBnd)) {
				properties.load(in);
			}
		String major = properties.getProperty("major");
		Objects.requireNonNull(major, "'major' must be set");
		String minor = properties.getProperty("minor");
		Objects.requireNonNull(minor, "'minor' must be set");

		int count = 0;
		bundles: for (String bundle : bundles) {
			Path bundlePath = Paths.get(bundle);
			Path bundleParent = bundlePath.getParent();
			Path a2JarDirectory = bundleParent != null ? a2Output.resolve(bundleParent).resolve(category)
					: a2Output.resolve(category);
			Path jarP = a2JarDirectory.resolve(bundlePath.getFileName() + "." + major + "." + minor + ".jar");

			Path targetJarP;
			if (bundle.startsWith(LIB_)) {// OS-specific
				Objects.requireNonNull(nativeTargetA2);
				if (bundle.startsWith(LIB_ + NATIVE_) // portable native
						|| bundle.startsWith(LIB_ + targetOs + "/" + NATIVE_)) {// OS-specific native
					targetJarP = nativeTargetA2.resolve(category).resolve(jarP.getFileName());
				} else if (bundle.startsWith(LIB_ + targetOs)) {// OS-specific portable
					targetJarP = targetA2.resolve(category).resolve(jarP.getFileName());
				} else { // ignore other OS
					continue bundles;
				}
			} else {
				targetJarP = targetA2.resolve(a2Output.relativize(jarP));
			}

			if (uninstall) { // uninstall
				if (Files.exists(targetJarP)) {
					Files.delete(targetJarP);
					logger.log(DEBUG, "Removed " + targetJarP);
					count++;
				}
				Path targetParent = targetJarP.getParent();
				if (targetParent.startsWith(targetA2))
					deleteEmptyParents(targetA2, targetParent);
				if (nativeTargetA2 != null && targetParent.startsWith(nativeTargetA2))
					deleteEmptyParents(nativeTargetA2, targetParent);
			} else { // install
				Files.createDirectories(targetJarP.getParent());
				boolean update = Files.exists(targetJarP);
				Files.copy(jarP, targetJarP, StandardCopyOption.REPLACE_EXISTING);
				logger.log(DEBUG, (update ? "Updated " : "Installed ") + targetJarP);
				count++;
			}
		}
		logger.log(INFO, uninstall ? count + " bundles removed" : count + " bundles installed or updated");
	}

	/** Extracts an argument which must be unique. */
	String singleArg(Map<String, List<String>> options, String arg, boolean mandatory) {
		List<String> values = options.get(arg);
		if (values == null || values.size() == 0)
			if (mandatory)
				throw new IllegalArgumentException(arg + " argument must be set");
			else
				return null;
		if (values.size() != 1)
			throw new IllegalArgumentException("One and only one " + arg + " arguments must be specified");
		return values.get(0);
	}

	/** Extracts an argument which can have multiple values. */
	List<String> multiArg(Map<String, List<String>> options, String arg, boolean mandatory) {
		List<String> values = options.get(arg);
		if (mandatory && values == null)
			throw new IllegalArgumentException(arg + " argument must be set");
		return values != null ? values : new ArrayList<>();
	}

	/** Delete empty parent directory up to the base directory (included). */
	void deleteEmptyParents(Path baseDir, Path targetParent) throws IOException {
		if (!targetParent.startsWith(baseDir))
			throw new IllegalArgumentException(targetParent + " does not start with " + baseDir);
		if (!Files.exists(baseDir))
			return;
		if (!Files.exists(targetParent)) {
			deleteEmptyParents(baseDir, targetParent.getParent());
			return;
		}
		if (!Files.isDirectory(targetParent))
			throw new IllegalArgumentException(targetParent + " must be a directory");
		boolean isA2target = Files.isSameFile(baseDir, targetParent);
		if (!Files.list(targetParent).iterator().hasNext()) {
			Files.delete(targetParent);
			if (isA2target)
				return;// stop after deleting A2 base
			deleteEmptyParents(baseDir, targetParent.getParent());
		}
	}

	/** Package a single bundle. */
	void createBundle(String branch, String bundle, String category) throws IOException {
		final Path bundleSourceBase;
		if (!Files.exists(execDirectory.resolve(bundle))) {
			logger.log(WARNING,
					"Bundle " + bundle + " not found in " + execDirectory + ", assuming this is this directory.");
			bundleSourceBase = execDirectory;
		} else {
			bundleSourceBase = execDirectory.resolve(bundle);
		}
		Path srcP = bundleSourceBase.resolve("src");

		Path compiled = buildBase.resolve(bundle);
		String bundleSymbolicName = bundleSourceBase.getFileName().toString();

		// Metadata
		Properties properties = new Properties();
		Path argeoBnd = argeoBuildBase.resolve("argeo.bnd");
		try (InputStream in = Files.newInputStream(argeoBnd)) {
			properties.load(in);
		}

		if (branch != null) {
			Path branchBnd = sdkSrcBase.resolve("sdk/branches/" + branch + ".bnd");
			if (Files.exists(branchBnd))
				try (InputStream in = Files.newInputStream(branchBnd)) {
					properties.load(in);
				}
		}

		Path bndBnd = bundleSourceBase.resolve("bnd.bnd");
		if (Files.exists(bndBnd))
			try (InputStream in = Files.newInputStream(bndBnd)) {
				properties.load(in);
			}

		// Normalise
		if (!properties.containsKey("Bundle-SymbolicName"))
			properties.put("Bundle-SymbolicName", bundleSymbolicName);

		// Calculate MANIFEST
		Path binP = compiled.resolve("bin");
		if (!Files.exists(binP))
			Files.createDirectories(binP);
		Manifest manifest;
		try (Analyzer bndAnalyzer = new Analyzer()) {
			bndAnalyzer.setProperties(properties);
			Jar jar = new Jar(bundleSymbolicName, binP.toFile());
			bndAnalyzer.setJar(jar);
			manifest = bndAnalyzer.calcManifest();
		} catch (Exception e) {
			throw new RuntimeException("Bnd analysis of " + compiled + " failed", e);
		}

		String major = properties.getProperty("major");
		Objects.requireNonNull(major, "'major' must be set");
		String minor = properties.getProperty("minor");
		Objects.requireNonNull(minor, "'minor' must be set");

		// Write manifest
		Path manifestP = compiled.resolve("META-INF/MANIFEST.MF");
		Files.createDirectories(manifestP.getParent());
		try (OutputStream out = Files.newOutputStream(manifestP)) {
			manifest.write(out);
		}

		// Load excludes
		List<PathMatcher> excludes = new ArrayList<>();
		Path excludesP = argeoBuildBase.resolve("excludes.txt");
		for (String line : Files.readAllLines(excludesP)) {
			PathMatcher pathMatcher = excludesP.getFileSystem().getPathMatcher("glob:" + line);
			excludes.add(pathMatcher);
		}

		Path bundleParent = Paths.get(bundle).getParent();
		Path a2JarDirectory = bundleParent != null ? a2Output.resolve(bundleParent).resolve(category)
				: a2Output.resolve(category);
		Path jarP = a2JarDirectory.resolve(compiled.getFileName() + "." + major + "." + minor + ".jar");
		Files.createDirectories(jarP.getParent());

		try (JarOutputStream jarOut = new JarOutputStream(Files.newOutputStream(jarP), manifest)) {
			jarOut.setLevel(Deflater.DEFAULT_COMPRESSION);
			// add all classes first
			Files.walkFileTree(binP, new SimpleFileVisitor<Path>() {
				@Override
				public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException {
					jarOut.putNextEntry(new JarEntry(binP.relativize(file).toString()));
					Files.copy(file, jarOut);
					return FileVisitResult.CONTINUE;
				}
			});

			// add resources
			Files.walkFileTree(bundleSourceBase, new SimpleFileVisitor<Path>() {
				@Override
				public FileVisitResult preVisitDirectory(Path dir, BasicFileAttributes attrs) throws IOException {
					// skip output directory if it happens to be within the sources
					if (Files.isSameFile(sdkBuildBase, dir))
						return FileVisitResult.SKIP_SUBTREE;

					// skip excluded patterns
					Path relativeP = bundleSourceBase.relativize(dir);
					for (PathMatcher exclude : excludes)
						if (exclude.matches(relativeP))
							return FileVisitResult.SKIP_SUBTREE;

					return FileVisitResult.CONTINUE;
				}

				@Override
				public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException {
					Path relativeP = bundleSourceBase.relativize(file);
					for (PathMatcher exclude : excludes)
						if (exclude.matches(relativeP))
							return FileVisitResult.CONTINUE;
					// skip JavaScript source maps
					if (sourceBundles && file.getFileName().toString().endsWith(".map"))
						return FileVisitResult.CONTINUE;

					JarEntry entry = new JarEntry(relativeP.toString());
					jarOut.putNextEntry(entry);
					Files.copy(file, jarOut);
					return FileVisitResult.CONTINUE;
				}
			});

			if (Files.exists(srcP)) {
				// Add all resources from src/
				Files.walkFileTree(srcP, new SimpleFileVisitor<Path>() {
					@Override
					public FileVisitResult preVisitDirectory(Path dir, BasicFileAttributes attrs) throws IOException {
						// skip directories ending with .js
						// TODO find something more robust?
						if (dir.getFileName().toString().endsWith(".js"))
							return FileVisitResult.SKIP_SUBTREE;
						return super.preVisitDirectory(dir, attrs);
					}

					@Override
					public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException {
						if (file.getFileName().toString().endsWith(".java")
								|| file.getFileName().toString().endsWith(".class"))
							return FileVisitResult.CONTINUE;
						jarOut.putNextEntry(new JarEntry(srcP.relativize(file).toString()));
						if (!Files.isDirectory(file))
							Files.copy(file, jarOut);
						return FileVisitResult.CONTINUE;
					}
				});

				// add sources
				// TODO add effective BND, Eclipse project file, etc., in order to be able to
				// repackage
				if (!sourceBundles) {
					copySourcesToJar(srcP, jarOut, "OSGI-OPT/src/");
				}
			}

			// add legal notices and licenses
			for (Path p : listLegalFilesToInclude(bundleSourceBase).values()) {
				jarOut.putNextEntry(new JarEntry(p.getFileName().toString()));
				Files.copy(p, jarOut);
			}
		}

		if (sourceBundles) {// create separate sources jar
			Path a2srcJarDirectory = bundleParent != null ? a2srcOutput.resolve(bundleParent).resolve(category)
					: a2srcOutput.resolve(category);
			Files.createDirectories(a2srcJarDirectory);
			Path srcJarP = a2srcJarDirectory.resolve(compiled.getFileName() + "." + major + "." + minor + ".src.jar");
			createSourceBundle(bundleSymbolicName, manifest, bundleSourceBase, srcP, srcJarP);
		}
	}

	/** Create a separate bundle containing the sources. */
	void createSourceBundle(String bundleSymbolicName, Manifest manifest, Path bundleSourceBase, Path srcP,
			Path srcJarP) throws IOException {
		Manifest srcManifest = new Manifest();
		srcManifest.getMainAttributes().put(Attributes.Name.MANIFEST_VERSION, "1.0");
		srcManifest.getMainAttributes().putValue("Bundle-SymbolicName", bundleSymbolicName + ".src");
		srcManifest.getMainAttributes().putValue("Bundle-Version",
				manifest.getMainAttributes().getValue("Bundle-Version").toString());

		boolean isJsBundle = bundleSymbolicName.endsWith(".js");
		if (!isJsBundle) {
			srcManifest.getMainAttributes().putValue("Eclipse-SourceBundle",
					bundleSymbolicName + ";version=\"" + manifest.getMainAttributes().getValue("Bundle-Version"));

			try (JarOutputStream srcJarOut = new JarOutputStream(Files.newOutputStream(srcJarP), srcManifest)) {
				copySourcesToJar(srcP, srcJarOut, "");
				// add legal notices and licenses
				for (Path p : listLegalFilesToInclude(bundleSourceBase).values()) {
					srcJarOut.putNextEntry(new JarEntry(p.getFileName().toString()));
					Files.copy(p, srcJarOut);
				}
			}
		} else {// JavaScript source maps
			srcManifest.getMainAttributes().putValue("Fragment-Host", bundleSymbolicName + ";bundle-version=\""
					+ manifest.getMainAttributes().getValue("Bundle-Version"));
			try (JarOutputStream srcJarOut = new JarOutputStream(Files.newOutputStream(srcJarP), srcManifest)) {
				Files.walkFileTree(bundleSourceBase, new SimpleFileVisitor<Path>() {
					@Override
					public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException {
						Path relativeP = bundleSourceBase.relativize(file);
						if (!file.getFileName().toString().endsWith(".map"))
							return FileVisitResult.CONTINUE;
						JarEntry entry = new JarEntry(relativeP.toString());
						srcJarOut.putNextEntry(entry);
						Files.copy(file, srcJarOut);
						return FileVisitResult.CONTINUE;
					}
				});
			}
		}
	}

	/** List the relevant legal files to include, from the SDK source base. */
	Map<String, Path> listLegalFilesToInclude(Path bundleBase) throws IOException {
		Map<String, Path> toInclude = new HashMap<>();
		if (!noSdkLegal) {
			DirectoryStream<Path> sdkSrcLegal = Files.newDirectoryStream(sdkSrcBase, (p) -> {
				String fileName = p.getFileName().toString();
				return switch (fileName) {
				case "NOTICE":
				case "LICENSE":
				case "COPYING":
				case "COPYING.LESSER":
					yield true;
				default:
					yield false;
				};
			});
			for (Path p : sdkSrcLegal)
				toInclude.put(p.getFileName().toString(), p);
		}
		for (Iterator<Map.Entry<String, Path>> entries = toInclude.entrySet().iterator(); entries.hasNext();) {
			Map.Entry<String, Path> entry = entries.next();
			Path inBundle = bundleBase.resolve(entry.getValue().getFileName());
			// remove file if it is also defined at bundle level
			// since it has already been copied
			// and has priority
			if (Files.exists(inBundle))
				entries.remove();
		}
		return toInclude;
	}

	/*
	 * UTILITIES
	 */
	/** Add sources to a jar file */
	void copySourcesToJar(Path srcP, JarOutputStream srcJarOut, String prefix) throws IOException {
		Files.walkFileTree(srcP, new SimpleFileVisitor<Path>() {
			@Override
			public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException {
				srcJarOut.putNextEntry(new JarEntry(prefix + srcP.relativize(file).toString()));
				if (!Files.isDirectory(file))
					Files.copy(file, srcJarOut);
				return FileVisitResult.CONTINUE;
			}
		});
	}

	/**
	 * Recursively find the base source directory (which contains the
	 * <code>{@value #SDK_MK}</code> file).
	 */
	Path findSdkMk(Path directory) {
		Path sdkMkP = directory.resolve(SDK_MK);
		if (Files.exists(sdkMkP)) {
			return sdkMkP.toAbsolutePath();
		}
		if (directory.getParent() == null)
			return null;
		return findSdkMk(directory.getParent());
	}

	/**
	 * Reads Makefile variable assignments of the form =, :=, or ?=, ignoring white
	 * spaces. To be used with very simple included Makefiles only.
	 */
	Map<String, String> readMakefileVariables(Path path) throws IOException {
		Map<String, String> context = new HashMap<>();
		List<String> sdkMkLines = Files.readAllLines(path);
		lines: for (String line : sdkMkLines) {
			StringTokenizer st = new StringTokenizer(line, " :=?");
			if (!st.hasMoreTokens())
				continue lines;
			String key = st.nextToken();
			if (!st.hasMoreTokens())
				continue lines;
			String value = st.nextToken();
			if (st.hasMoreTokens()) // probably not a simple variable assignment
				continue lines;
			context.put(key, value);
		}
		return context;
	}

	/** Main entry point, interpreting actions and arguments. */
	public static void main(String... args) {
		if (args.length == 0)
			throw new IllegalArgumentException("At least an action must be provided");
		int actionIndex = 0;
		String action = args[actionIndex];
		if (args.length > actionIndex + 1 && !args[actionIndex + 1].startsWith("-"))
			throw new IllegalArgumentException(
					"Action " + action + " must be followed by an option: " + Arrays.asList(args));

		Map<String, List<String>> options = new HashMap<>();
		String currentOption = null;
		for (int i = actionIndex + 1; i < args.length; i++) {
			if (args[i].startsWith("-")) {
				currentOption = args[i];
				if (!options.containsKey(currentOption))
					options.put(currentOption, new ArrayList<>());

			} else {
				options.get(currentOption).add(args[i]);
			}
		}

		try {
			Make argeoMake = new Make();
			switch (action) {
			case "compile" -> argeoMake.compile(options);
			case "bundle" -> argeoMake.bundle(options);
			case "all" -> argeoMake.all(options);
			case "install" -> argeoMake.install(options, false);
			case "uninstall" -> argeoMake.install(options, true);

			default -> throw new IllegalArgumentException("Unkown action: " + action);
			}

			long jvmUptime = ManagementFactory.getRuntimeMXBean().getUptime();
			logger.log(INFO, "Make.java action '" + action + "' successfully completed after " + (jvmUptime / 1000)
					+ "." + (jvmUptime % 1000) + " s");
		} catch (Exception e) {
			long jvmUptime = ManagementFactory.getRuntimeMXBean().getUptime();
			logger.log(ERROR, "Make.java action '" + action + "' failed after " + (jvmUptime / 1000) + "."
					+ (jvmUptime % 1000) + " s", e);
			System.exit(1);
		}
	}

	/** A jar file in A2 format */
	static class A2Jar {
		final Path path;
		final String name;
		final int major;
		final int minor;

		A2Jar(Path path) {
			try {
				this.path = path;
				String fileName = path.getFileName().toString();
				fileName = fileName.substring(0, fileName.lastIndexOf('.'));
				minor = Integer.parseInt(fileName.substring(fileName.lastIndexOf('.') + 1));
				fileName = fileName.substring(0, fileName.lastIndexOf('.'));
				major = Integer.parseInt(fileName.substring(fileName.lastIndexOf('.') + 1));
				name = fileName.substring(0, fileName.lastIndexOf('.'));
			} catch (Exception e) {
				throw new IllegalArgumentException("Badly formatted A2 jar " + path, e);
			}
		}
	}

	/**
	 * An ECJ {@link CompilationProgress} printing a progress bar while compiling.
	 */
	static class MakeCompilationProgress extends CompilationProgress {
		private int totalWork;
		private long currentChunk = 0;
		private long chunksCount = 80;

		@Override
		public void worked(int workIncrement, int remainingWork) {
			if (!logger.isLoggable(Level.INFO)) // progress bar only at INFO level
				return;
			long chunk = ((totalWork - remainingWork) * chunksCount) / totalWork;
			if (chunk != currentChunk) {
				currentChunk = chunk;
				for (long i = 0; i < currentChunk; i++) {
					System.out.print("#");
				}
				for (long i = currentChunk; i < chunksCount; i++) {
					System.out.print("-");
				}
				System.out.print("\r");
			}
			if (remainingWork == 0)
				System.out.print("\n");
		}

		@Override
		public void setTaskName(String name) {
		}

		@Override
		public boolean isCanceled() {
			return false;
		}

		@Override
		public void done() {
		}

		@Override
		public void begin(int remainingWork) {
			this.totalWork = remainingWork;
		}
	}
}
