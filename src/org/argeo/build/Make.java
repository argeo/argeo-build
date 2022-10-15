package org.argeo.build;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.PrintWriter;
import java.lang.management.ManagementFactory;
import java.nio.file.FileVisitResult;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.PathMatcher;
import java.nio.file.Paths;
import java.nio.file.SimpleFileVisitor;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Properties;
import java.util.StringJoiner;
import java.util.StringTokenizer;
import java.util.jar.JarEntry;
import java.util.jar.JarOutputStream;
import java.util.jar.Manifest;

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
	/** Name of the local-specific Makefile (sdk.mk). */
	final static String SDK_MK = "sdk.mk";

	/** The execution directory (${user.dir}). */
	final Path execDirectory;
	/** Base of the source code, typically the cloned git repository. */
	final Path sdkSrcBase;
	/**
	 * The base of the builder, typically a submodule pointing to the public
	 * argeo-build directory.
	 */
	final Path argeoBuildBase;
	/** The base of the build for all layers. */
	final Path sdkBuildBase;
	/** The base of the build for this layer. */
	final Path buildBase;
	/** The base of the a2 output for all layers. */
	final Path a2Output;

	/** Constructor initialises the base directories. */
	public Make() throws IOException {
		execDirectory = Paths.get(System.getProperty("user.dir"));
		Path sdkMkP = findSdkMk(execDirectory);
		Objects.requireNonNull(sdkMkP, "No " + SDK_MK + " found under " + execDirectory);

		Map<String, String> context = new HashMap<>();
		List<String> sdkMkLines = Files.readAllLines(sdkMkP);
		lines: for (String line : sdkMkLines) {
			StringTokenizer st = new StringTokenizer(line, " :=");
			if (!st.hasMoreTokens())
				continue lines;
			String key = st.nextToken();
			if (!st.hasMoreTokens())
				continue lines;
			String value = st.nextToken();
			context.put(key, value);
		}

		sdkSrcBase = Paths.get(context.computeIfAbsent("SDK_SRC_BASE", (key) -> {
			throw new IllegalStateException(key + " not found");
		})).toAbsolutePath();
		argeoBuildBase = sdkSrcBase.resolve("sdk/argeo-build");

		sdkBuildBase = Paths.get(context.computeIfAbsent("SDK_BUILD_BASE", (key) -> {
			throw new IllegalStateException(key + " not found");
		})).toAbsolutePath();
		buildBase = sdkBuildBase.resolve(sdkSrcBase.getFileName());
		a2Output = sdkBuildBase.resolve("a2");
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
	@SuppressWarnings("restriction")
	void compile(Map<String, List<String>> options) throws IOException {
		List<String> bundles = options.get("--bundles");
		Objects.requireNonNull(bundles, "--bundles argument must be set");
		if (bundles.isEmpty())
			return;

		List<String> a2Categories = options.getOrDefault("--dep-categories", new ArrayList<>());
		List<String> a2Bases = options.getOrDefault("--a2-bases", new ArrayList<>());
		if (a2Bases.isEmpty()) {
			a2Bases.add(a2Output.toString());
		}

		List<String> compilerArgs = new ArrayList<>();

		Path ecjArgs = argeoBuildBase.resolve("ecj.args");
		compilerArgs.add("@" + ecjArgs);

		// classpath
		if (!a2Categories.isEmpty()) {
			compilerArgs.add("-cp");
			StringJoiner classPath = new StringJoiner(File.pathSeparator);
			for (String a2Base : a2Bases) {
				for (String a2Category : a2Categories) {
					Path a2Dir = Paths.get(a2Base).resolve(a2Category);
					if (!Files.exists(a2Dir))
						Files.createDirectories(a2Dir);
					for (Path jarP : Files.newDirectoryStream(a2Dir,
							(p) -> p.getFileName().toString().endsWith(".jar"))) {
						classPath.add(jarP.toString());
					}
				}
			}
			compilerArgs.add(classPath.toString());
		}

		// sources
		for (String bundle : bundles) {
			StringBuilder sb = new StringBuilder();
			sb.append(execDirectory.resolve(bundle).resolve("src"));
			sb.append("[-d");
			compilerArgs.add(sb.toString());
			sb = new StringBuilder();
			sb.append(buildBase.resolve(bundle).resolve("bin"));
			sb.append("]");
			compilerArgs.add(sb.toString());
		}

		boolean success = org.eclipse.jdt.core.compiler.batch.BatchCompiler.compile(
				compilerArgs.toArray(new String[compilerArgs.size()]), new PrintWriter(System.out),
				new PrintWriter(System.err), new MakeCompilationProgress());
		if (!success) // kill the process if compilation failed
			System.exit(1);
	}

	/** Package the bundles. */
	void bundle(Map<String, List<String>> options) throws IOException {
		// check arguments
		List<String> bundles = options.get("--bundles");
		Objects.requireNonNull(bundles, "--bundles argument must be set");
		if (bundles.isEmpty())
			return;

		List<String> categories = options.get("--category");
		Objects.requireNonNull(bundles, "--bundles argument must be set");
		if (categories.size() != 1)
			throw new IllegalArgumentException("One and only one category must be specified");
		String category = categories.get(0);

		// create jars
		for (String bundle : bundles)
			createBundle(bundle, category);
	}

	/*
	 * UTILITIES
	 */
	/** Package a single bundle. */
	void createBundle(String bundle, String category) throws IOException {
		Path source = execDirectory.resolve(bundle);
		Path compiled = buildBase.resolve(bundle);
		String bundleSymbolicName = source.getFileName().toString();

		// Metadata
		Properties properties = new Properties();
		Path argeoBnd = argeoBuildBase.resolve("argeo.bnd");
		try (InputStream in = Files.newInputStream(argeoBnd)) {
			properties.load(in);
		}
		// FIXME make it configurable
		Path branchBnd = sdkSrcBase.resolve("cnf/unstable.bnd");
		try (InputStream in = Files.newInputStream(branchBnd)) {
			properties.load(in);
		}

		Path bndBnd = source.resolve("bnd.bnd");
		try (InputStream in = Files.newInputStream(bndBnd)) {
			properties.load(in);
		}

		// Normalise
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

		String major = properties.getProperty("MAJOR");
		Objects.requireNonNull(major, "MAJOR must be set");
		String minor = properties.getProperty("MINOR");
		Objects.requireNonNull(minor, "MINOR must be set");

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
			Files.walkFileTree(source, new SimpleFileVisitor<Path>() {

				@Override
				public FileVisitResult preVisitDirectory(Path dir, BasicFileAttributes attrs) throws IOException {
					Path relativeP = source.relativize(dir);
					for (PathMatcher exclude : excludes)
						if (exclude.matches(relativeP))
							return FileVisitResult.SKIP_SUBTREE;

					return FileVisitResult.CONTINUE;
				}

				@Override
				public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException {
					Path relativeP = source.relativize(file);
					for (PathMatcher exclude : excludes)
						if (exclude.matches(relativeP))
							return FileVisitResult.CONTINUE;
					JarEntry entry = new JarEntry(relativeP.toString());
					jarOut.putNextEntry(entry);
					Files.copy(file, jarOut);
					return FileVisitResult.CONTINUE;
				}

			});

			// add sources
			// TODO add effective BND, Eclipse project file, etc., in order to be able to
			// repackage
			Path srcP = source.resolve("src");
			Files.walkFileTree(srcP, new SimpleFileVisitor<Path>() {

				@Override
				public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException {
					jarOut.putNextEntry(new JarEntry("OSGI-OPT/src/" + srcP.relativize(file).toString()));
					Files.copy(file, jarOut);
					return FileVisitResult.CONTINUE;
				}
			});

		}

	}

	/**
	 * Recursively find the base source directory (which contains the
	 * <code>{@value #SDK_MK}</code> file).
	 */
	private Path findSdkMk(Path directory) {
		Path sdkMkP = directory.resolve(SDK_MK);
		if (Files.exists(sdkMkP)) {
			return sdkMkP.toAbsolutePath();
		}
		if (directory.getParent() == null)
			return null;
		return findSdkMk(directory.getParent());

	}

	/** Main entry point, interpreting actions and arguments. */
	public static void main(String... args) {
		try {
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

			Make argeoMake = new Make();
			switch (action) {
			case "compile" -> argeoMake.compile(options);
			case "bundle" -> argeoMake.bundle(options);
			case "all" -> argeoMake.all(options);

			default -> throw new IllegalArgumentException("Unkown action: " + action);
			}

			long jvmUptime = ManagementFactory.getRuntimeMXBean().getUptime();
			System.out.println("Completed after " + jvmUptime + " ms");
		} catch (Exception e) {
			e.printStackTrace();
			System.exit(1);
		}
	}

	/**
	 * An ECJ {@link CompilationProgress} printing a progress bar while compiling.
	 */
	class MakeCompilationProgress extends CompilationProgress {
		int totalWork;
		long currentChunk = 0;

		long chunksCount = 80;

		@Override
		public void worked(int workIncrement, int remainingWork) {
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
