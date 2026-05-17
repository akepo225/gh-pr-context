#!/usr/bin/env python3
import sys

VERSION = "0.2.5"


def die(message):
    print(f"error: {message}", file=sys.stderr)
    return 1


def usage():
    print("usage: gh-pr-context [--version|--help]")
    print("")
    print("options:")
    print("  --version       Show version")
    print("  -h, --help      Show this message")
    print("")
    print("note: Windows Python runtime currently supports --version and --help only")


def main(argv):
    if sys.version_info < (3, 11):
        return die("python 3.11+ is required")

    if not argv:
        usage()
        return 1

    command = argv[0]
    if command == "--version":
        print(f"gh-pr-context {VERSION}")
        return 0
    if command in ("-h", "--help"):
        usage()
        return 0

    return die("Windows Python runtime currently supports --version and --help only")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
