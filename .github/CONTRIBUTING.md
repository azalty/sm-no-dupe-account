# Contribution guidelines
Thanks for wanting to contribute to this project!

So that the code stays clean and readable, using the same coding style is really important.

## Important things
If you want to add a feature, report a bug etc.., please [create an issue](https://github.com/azalty/sm-no-dupe-account/issues) first!

I prefer to do the code myself. If you have any idea/tip for the code, please send it in the issue.\
However, if it is a simple bug to fix (< 10 lines approximatively), you can create a pull request.

**Why?** Because your way of doing it could cause problems for the future, or problems for my own understanding.\
I don't like to deny Pull Requests that have been worked on for hours.

**Always discuss about important changes before doing them!**\
The best solution is to ask me if you can fix it yourself :)

## Indentation type
The indentation type used is the Allman style: https://en.wikipedia.org/wiki/Indentation_style#Allman_style \
You can see an example below:

```
// Function
void FunctionName()
{
	// Statements (if, while, for)
	while (x == y)
	{
		something();
		somethingelse();
	}
	
	if (something)
	{
		doThat();
		doThat2();
	}
}
```
Additionally, no brackets are needed for conditions that only do one thing.
```
// Prefered way
if (this)
	doSomething;

// Acceptable way
if (this)
{
	doSomething;
}
```

## Indentation method
Use tabulations (TAB) to do indentation.\
Please never ever use spaces.

Try to preserve indentation in empty lines:

:white_check_mark: Correct (select the text to see):
```
// Function
void FunctionName()
{
	doThat();
	
	doThat2();
}
```

❌ Incorrect (select the text to see):
```
// Function
void FunctionName()
{
	doThat();

	doThat2();
}
```

## Naming style (for variables, functions..)
**General rule:** use good variable names. Avoid using 'x' or 'y' as variable names, they should be explicit.

---

**Global variables:** start with 'g_' (global) and then the first letter of the type.\
You can then write the name of the variable, the first letter being a capital letter:
- g_iTest (global int with name Test)
- g_bTest (global bool with name Test)
- g_sTest (global string (array of characters))
- g_hTest (global handle (also used for methodmaps that are handles, such as a Database, KeyValues

These rules are not always enforced. If often use different names, but it's a good practice to take.\
If you have any other prefered way to do it, please ask me :)

---

**Local (non-global) variables:** I don't really care. Just don't start with a capital letter in general.\
These examples are all valid:
- int iCount
- int iSmallCount
- int small_count
- int smallCount
- int count
- bool bExists
- bool kick
- char sBuffer[32]
- char sBuffer[32]

## Try to avoid bracket nesting with returns

(stolen from [MyJailbreak's guidelines](https://github.com/shanapu/MyJailbreak/blob/148fccdc6383f3570c1df7b0ff4fcc6d41bcde6d/CONTRIBUTING.md))

Examples:

:white_check_mark: Good:
```
void function()
{
	if (!check1)
		return;
	
	if (!check2)
		return;
	
	if (!check3)
		return;
	
	if (!check4)
		return;
	
	function2();
}
```
:x: Bad:
```
void function()
{
	if (check1)
	{
		if (check2)
		{
			if (check3)
			{
				if (check4)
				{
					function2();
				}
			}
		}
	}
}
```

## Space your code
:x: Avoid:
```
if(this||that||thisThing)
{
	int a=b+54+14+(87/14);
	function1();
	function2();
}
```
✅ Do:
```
if (this || that || thisThing)
{
	// You can shorten it a bit to increase readability, but don't be afraid to take more space.
	int a = b + 54 + 14 + (87/14);
	
	function1();
	function2();
}
```

✅ Take good habits, put spaces and commas (,) in good places:
```
// Define a function
void Function(int arg1, bool arg)
{
	// Call a function
	tryThis(1, true, 54, "test");
	
	// Loop
	for (int i; i <= MaxClients; i++)
	{
		...
	}
}
```

:x: A bit ugly:
```
// Define a function
void Function ( int arg1 ,bool arg)
{
	// Call a function
	tryThis ( 1 ,true, 54 , "test");
	
	// Loop
	for (int i;i <=MaxClients ;i++)
	{
		...
	}
}
```

Try to imitate the code's style in general.

---

### Thanks for reading, contributing, and using my plugin!
