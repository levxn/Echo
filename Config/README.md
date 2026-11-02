# Config

`meta_api_key.txt` is where your Meta Model API key goes.

1. Open `meta_api_key.txt` and replace the single line `PASTE_YOUR_META_API_KEY_HERE` with your key
   (one line, no quotes, no spaces).
2. Run `Tools/set_api_key.sh` to install it into the app.

The file is **gitignored**, so it never leaves your machine. The app copies the key into the simulator's
own container and never logs it. While the file still holds the placeholder, Echo runs on its clearly
labeled offline stub instead of calling Meta.
