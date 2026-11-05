# lists

Checklists shared by every member, and a board of the same items (PLAN §6, D36). One markup for both views. An item has a column, one
column closes, and done means being in it. Columns come from the template, with no editor. A change runs off the loop, then says on
`lists.list:<id>` (`.Latest` per column) which columns changed, and each page fetches them: a whole column can pass the hub's 64 KiB. Moves
are buttons in forms; dragging posts the same form. Packages: `lists`, `models`, `views`, `web`, `storetest`. SQLite only. It owns `/lists`,
its own prefix.
