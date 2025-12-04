package org.argeo.build;

import static java.nio.file.FileVisitResult.CONTINUE;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.DirectoryStream;
import java.nio.file.FileVisitResult;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.SimpleFileVisitor;
import java.nio.file.attribute.BasicFileAttributes;
import java.util.spi.ToolProvider;

/**
 * Package some artifacts (typically JNI libraries) as jmod, in order to be able
 * to create custom Java runtimes with jlink.
 */
public class PackageJmods {
	/** A2 repository base. */
	final Path a2Base;

	private final ToolProvider jmodTool;
	private final ToolProvider javacTool;

	PackageJmods(Path a2Base) {
		this.a2Base = a2Base;

		this.jmodTool = ToolProvider.findFirst("jmod").orElseThrow();
		this.javacTool = ToolProvider.findFirst("javac").orElseThrow();
	}

	void processJmods() {
		try {
			int javaVersion = Runtime.version().feature();
			Path jmodsDir = a2Base.resolve("jmods").resolve(Integer.toString(javaVersion));
			Files.createDirectories(jmodsDir);
			try (DirectoryStream<Path> multiArchDirs = Files.newDirectoryStream(a2Base.resolve("lib"),
					(p) -> Files.isDirectory(p))) {
				multiArchDirs: for (Path multiArchDir : multiArchDirs) {
					String multiArchDirName = multiArchDir.getFileName().toString();
					if (!(multiArchDirName.startsWith("x86_64-") || multiArchDirName.startsWith("aarch64-")))
						continue multiArchDirs;// TODO make it more robust
					Path jmodBuildDir = multiArchDir.resolve("jmods");
					if (!Files.exists(jmodBuildDir))
						continue multiArchDirs;
					Path jmodsDirNative = multiArchDir.resolve("jmods").resolve(Integer.toString(javaVersion));
					Files.createDirectories(jmodsDirNative);
					try (DirectoryStream<Path> jmodDirs = Files.newDirectoryStream(jmodBuildDir,
							(p) -> Files.isDirectory(p))) {
						jmodDirs: for (Path jmodDir : jmodDirs) {
							String moduleName = jmodDir.getFileName().toString();
							if (moduleName.indexOf('.') < 0)
								continue jmodDirs; // skip Java version dirs
							Path jmodJavaDir = jmodDir.resolve("java");
							Files.createDirectories(jmodJavaDir);
							Path jmodClassesDir = jmodDir.resolve("classes");
							Files.createDirectories(jmodClassesDir);
							Path moduleInfoJava = jmodJavaDir.resolve("module-info.java");
							Files.writeString(moduleInfoJava, "module " + moduleName + " {}",
									StandardCharsets.US_ASCII);
							javacTool.run(System.out, System.err, "-d", jmodClassesDir.toString(),
									moduleInfoJava.toString());

							Path jmodLibDir = jmodDir.resolve("lib");
							String jmodVersion = Files.readString(jmodDir.resolve("VERSION.txt"));
							Path jmodPath = jmodsDirNative.resolve(multiArchDirName + "-" + moduleName + ".jmod");
							if (Files.exists(jmodPath))
								Files.delete(jmodPath);
							jmodTool.run(System.out, System.err, "create", //
									"--module-version", jmodVersion, //
									"--class-path", jmodClassesDir.toString(), //
									"--libs", jmodLibDir.toString(), //
									jmodPath.toString());
							System.out.println("Created JMOD " + jmodPath);
						}
					}
				}
			}
		} catch (IOException e) {
			throw new UncheckedIOException("Cannot process jmods in " + a2Base, e);
		}
	}

	public static void main(String[] args) {
		if (args.length < 1) {
			System.err.println("Usage: <path to a2 output dir>");
			System.exit(1);
		}
		Path a2Base = Paths.get(args[0]).toAbsolutePath().normalize();
		PackageJmods factory = new PackageJmods(a2Base);
		factory.processJmods();
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

}
