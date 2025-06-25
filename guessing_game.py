import tkinter as tk
import random

secret_number = random.randint(1, 10)

root = tk.Tk()
root.title("Number Guessing Game")

prompt = tk.Label(root, text="Guess a number between 1 and 10")
prompt.pack(pady=5)

entry = tk.Entry(root)
entry.pack(pady=5)

result_var = tk.StringVar()
result_label = tk.Label(root, textvariable=result_var)
result_label.pack(pady=5)


def check_guess():
    guess = entry.get()
    try:
        g = int(guess)
    except ValueError:
        result_var.set("Please enter a valid number")
        return

    if g == secret_number:
        result_var.set("Correct!")
        entry.config(state=tk.DISABLED)
        guess_button.config(state=tk.DISABLED)
    else:
        result_var.set("Wrong, try again")


guess_button = tk.Button(root, text="Guess", command=check_guess)
guess_button.pack(pady=5)

root.mainloop()
