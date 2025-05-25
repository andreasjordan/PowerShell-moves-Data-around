db = db.getSiblingDB("photoservice");
db.createUser({
  user: "photoservice",
  pwd: "Passw0rd!",
  roles: [ { role: "readWrite", db: "photoservice" } ]
});

db = db.getSiblingDB("stackexchange");
db.createUser({
  user: "stackexchange",
  pwd: "Passw0rd!",
  roles: [ { role: "readWrite", db: "stackexchange" } ]
});
