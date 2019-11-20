# Teampass API Wrapper

First, let's answer the questions:
- [what is it?](#About)
- [how to set it up?](#Install)
- [how to use it?](#Usage)
- [my thoughts on the API](#Limits)
- [how the things involved](#ChangeLog)

Let's go.

## About

This is a POSIX shell script that have very few dependencies.
Commands used should be available in most distributions, but:
- AWK
- JQ

## Install

First, download the script in your path:
```shell
# check it's ok
echo $PATH
# e.g. into /usr/local/bin using cURL
fdest=/usr/local/bin
fname=tpcli.sh
curl https//raw.githubcontent.com/gilcot/tapiw/master/$fname -o $fdest/$fname
```
Second, make it executable:
```shell
chmod a+x $fdest/$fname
ls -l $fdest/$fname
```
Last, create your setup file:
```shell
$ cat <<EOF >/etc/tp_cli.rc
TEAMPASS_URL="https://teampass.example.org"
TEAMPASS_APIKEY="503E-ca1cE"
EOF
```
Install also the packages listed early according to your distro.

## Usage

It's first purpose was to ease the use of the API from scripts.  
In another words, it's a library to use that way:
```shell
# define variables used here
url="https://teampass.example.org"
key="503E-ca1cE"
# read fourth entry (login?) of folder 666
tpcli.sh -u "$url" -k "$key" -c folder -i 666 | cut -f 4
# read fith (email?) and seventh (pw?) entries of item 9
tpcli.sh -u "$url" -k "$key" -c item -i 9 | cut -f 5,7
# find all Bob's entries dealing with sponges (in any field)
tpcli.sh -u "$url" -k "$key" -c userpw -i bob | grep sponge
```
The ease come from the fact that:
- you don't have to know and retype the API call everytime
(and, with named instead of positional parameters, you don't
care the order anymore, at least for reading&hellip;)
- the response is ready to be consumed with usual commands:
`sort`, `cut`, `awk`, etc.

The second purpose is to assist the user (interactive mode, use
the switch `-B` to revert and act like in a script.) by feeding
a form of needed values. So, previous example becomes:
```
$ cat ~/.tp_cli.rc
TEAMPASS_URL="https://teampass.example.org"
TEAMPASS_APIKEY="503E-ca1cE"
$ tpcli.sh -c item
Item Id?	20
label	login	url	pw
webdealauto	nils@yahoo.fr		od0@s'23E
$ tpcli.sh -c userpw
User Login?	nilstest
id	label	description	login	email	url	pw	folder_id	path
1	DNS server	For all DNS management	Admin	admin@dns.fr	http://mydn.fr	Ud9r^ G7	1	Folder #1
5	Motorola.com	Motorola customer portal	Jean-Paul	jp.maurice@gmail.com	https://www.motorola.com	Motorola.com	2	F2 - my new folder
$ tpcli.sh -c userfolders
User Login?	test
id	title	level	access_type
2	My new folder	1	NONE
5	Sub folder name	2	W
22	A very long folder name	2	W
```
That's handy when adding stuffs (with `-a add` instead of `-a read` which
is the default.) For example (not final prompts):
```
$ tpcli.sh -a add -c item
Label?	a new test entry
Password?	fo0b@r
Description?	for test purpose
folder Id?	12
Login?	none
Email?	jane@doe.com
Url?
Tags?
Any one can modify?	1
status	new_folder_id
folder created	56
```

Deletion (with `-a delete` then) is as easy as reading:
```
# from script delete item 7003
$ tpcli.sh -a delete 7003
# interactively delete an item
$ tpcli.sh -a delete
```

## Limits

This API is a joke in my humble opinion.

First things, it's not designed like others, in a regular way where you
would use just `/read/items/` to retrive all items and `/read/item/$Id`
to retrieve a specific item. OK, it has the original feature I like much:
`/read/items/$Id1;...;$IdN` That allow the retrieval of many items. But
why not `/read/items/0` or `/read/items/all` to get'em all?

Same thing for folders: there's no way to retrieve all the list to loop
over, but you can retrieve many knowing their Ids. Well, but why on earth
`/read/folder/$Id1;...;$IdN` instead of `/read/folders/$Id1;...;$IdN` ?!? 
Hold on, that's not all. Why have both `/read/folder/$Id` and
`/info/folder/$Id` ?!? It's a bit confusing...

Another thing to mention: not all components are usable via the API, or
is the documentation incomplete?

| component | read? | add? | info? | update? | delete? |
|-----------|-------|------|-------|---------|---------|
| item      | Yes   | Yes  | No    | Yes     | Yes     |
| folder    | Yes   | Yes  | Yes   | Yes     | Yes     |
| user      | No    | Yes  | No    | No      | No      |
| role      | No    | No   | No    | No      | No      |
| file      | Yes   | Yes  | list? | No      | No      |
| userfolder| Yes   | Yes  | No    | Yes     | Yes     |
| userpw    | Yes   | Yes  | No    | Yes     | Yes     |
| category  | No    | No   | No    | No      | No      |

There're the specific `/read/userpw/$Login` and `/read/userfolders/$Login`
to list items and folders attached to a user. To create and update them,
you have to use respectively `/add/folder/`/`/add/item/` and
`/update/folder/$Id`/`/update/item/$Id` That sounds good, and is the rare
good point I've noticed.

About addition and update, things are not regular either. In some case,
you must base64-encode each field/part delimited by semicoln. In another
case, you must base64-encode the whole fields/parts once grouped together.
I'm puzzled!

Last things. A key is needed to be able to talk to the API, good. But,
there's no http-authentication, what is bad bad bad. In fact the API key
give you full access, whereas it would be good that it's restricted by
some account rights  without reinventing the wheel (another roles matrix
for the keys.)  
To give a kind security illusion, there's some IP restriction possible.
But guess what? It apply to all keys, shit.

## ChangeLog

Following is the chronological evolution before versionning.

<dl>
<dt>0.0.0 2019-11-12</dt>
<dd>I've been playing with our instance without success
&hellip;till I notice the API wasn't enable. Once done,
I've able to experiment a little with the API.</dd>
<dt>0.1.0 2019-11-14</dt>
<dd>Putting the stuffs into a script to get item to read from
command line, and parse the returned JSON into tab delimited.</dd>
<dt>found 2019-11-15</dt>
<dd>Discovering Vadim Aleksandov worked on a CLI, but can't figure
out how to use it (see the first issue, it need patching first the
installed base.)</dd>
<dt>0.2.0 2019-11-18</dt>
<dd>New: default to prompting for values and add batch switch</dd>
<dd>New: add a batch mode option to disable prompting</dd>
<dt>0.3.0 2019-11-19</dt>
<dd>New: read almost all known components, after creating a common
get function.</dd>
<dd>Now: also add the support of the find method, but I found it a
bit useless</dd>
<dd>New: shared function to pass multiple Ids</dd>
<dt>0.3.1 2019-11-20</dt>
<dd>Fix: rework on get function to handle errors too.</dd>
<dt>0.4.0 2019-11-22</dt>
<dd>New: made a prompt and fail functions and refactorised the code
(it low the final size while providing a consistant behavieur.) </dd>
<dt>0.5.0 2019-11-23</dt>
<dd>New: many components synonyms for convenienece, plus both both singular and
plural forms each time.</dd>
<dd>New: deletion, addition and update actions now added, after making
the function able to handle the output (the dedicated part is a bit more
generic and called for both status and password) and making another one
to handle base64 encoding (and thus adds another dependancy).</dd>
<dt>found 2019-11-24</dt>
<dd>Discovering Jonathan Lestrelin worked on a CLI too, but it's based
on categories wich are not in use in our installation.</dd>
<dt>found 2019-11-25</dt>
<dd>Created this repository in order to share with the world.</dd>
<dt>0.6.0 2019-11-26</dt>
<dd>New: shortcut to add/delete folder with components
`publicfolder` and `userfolder` </dd>
<dd>New: add categories reading (but not tested.)</dd>
<dd>New: add undocumented reading folder descendant.</dd>
<dt>0.6.1 2019-11-26</dt>
<dd>Fix: after test from an old box, add fallback to CSV</dd>
<dt>0.7.0 2019-11-29</dt>
<dd>New: many actions/methods synonyms for convenience</dd>
<dt>0.7.1 2019-11-29</dt>
<dd>Fix: correct errors in encoding function</dd>
<dt>0.8.0 2019-11-29</dt>
<dd>New: addition of more synonyms for -a option</dd>
</dl>


