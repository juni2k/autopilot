# autopilot

Creates a shallow copy of a Git repository by committing almost nothing.

## Motivation

In 2021, GitHub released Copilot, which has been considered a
breakthrough in AI-assisted programming. For the first time in history,
*anyone* could produce something resembling functional code. Something
that a compiler would happily accept!

The system has been trained on publicly-available repositories (such as
mine) without any financial compensation, and ignoring any copyright
concerns along the way.

I consider this a moral trainwreck. And I do not want to use a platform
that behaves like a schoolyard bully, running around and profiting from
the work that contributors provided for free.

However, it's not straightforward to leave GitHub: apparently, a GitHub
profile is seen with the same importance as a business card. Employers
seem to care about those little green tiles on the profile page. Leaving
GitHub is like moving into a forest cabin: you become invisible.

This script takes care of that. It essentially mirrors *all of the
activity*, but *none of the code*.

## Usage

Assume a repo called "example".

First, create `example.conf`, next to `autopilot.pl`, with these
contents:

```
local_repo = /data/git/example.git
github_repo = git@github.com:you/example.git
mock_repo = ./example.mock
readme_template = ./example.md
git_name = Your Name
git_email = your@email.net
```

Then, create `example.md`:

```
This will become the readme file.
Fill these lines with anything you consider reasonable.

But don't forget to include at least one mention of
%COMMIT_HASH% or %COMMIT_SUBJECT%!

Those placeholders will be populated with data from the
original commit. If you omit those, Git will have nothing
to create a diff from.
```

Then, run: `perl autopilot.pl example.conf`.

## Todo

- automatically push the commits to GitHub

## License

lmao
