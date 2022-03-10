# Check patches against Tarantool development guidelines

This action checks the given Git revision range against Tarantool development
guidelines.

## How to use action from GitHub workflow

Add the following lines to the running steps:

```
  steps:
    ...
    - uses: actions/checkout@v2
      with:
        fetch-depth: 0
        ref: ${{ github.event.pull_request.head.sha }}
    - uses: tarantool/checkpatch/.github/actions/checkpatch@master
      with:
        revision-range: HEAD~${{ github.event.pull_request.commits }}..HEAD
    ...
```

Note, you can use the action only after the repo checkout.
